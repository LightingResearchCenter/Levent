function convertData

[githubDir,~,~] = fileparts(pwd);
circadianDir = fullfile(githubDir,'circadian');
d12packDir = fullfile(githubDir,'d12pack');
addpath(circadianDir,d12packDir);

CalibrationPath = '\\root\projects\DaysimeterAndDimesimeterReferenceFiles\recalibration2016\calibration_log.csv';

%% Condtruct folder paths
projectDir = '\\root\public\wardg3\MATLAB\LeventDataAnalysis\SubjectData';
croppedDir = fullfile(projectDir,'CroppedCDFs');
subjects = cellstr(num2str([11,12,13,14,15,16,17,18,19,20,22,24,25,27,28,29]'));
nSub = numel(subjects);
crpSubDirs = fullfile(croppedDir,subjects);

%% Define time zones
TimeZoneLaunch = 'Europe/Istanbul';
TimeZoneDeploy = 'Europe/Istanbul';

%% Import Calibration Data
cal = readtable(CalibrationPath);
cal.Properties.VariableNames{1} = 'SN';

%% Inventory files
for iSub1 = nSub:-1:1
    thisCrpDir = crpSubDirs{iSub1};
    
    lsCDF  = dir([thisCrpDir,filesep,'*.cdf']);
    lsBed  = dir([thisCrpDir,filesep,'*Sleep_Log.xlsx']);
    lsWork = dir([thisCrpDir,filesep,'*Workday_log.xlsx']);
    
    theseCrpPaths  = fullfile(thisCrpDir,{lsCDF.name}');
    theseOrgPaths  = regexprep(theseCrpPaths,'CroppedCDFs','OriginalData');
    theseDataPaths = regexprep(theseOrgPaths,'\.cdf','-DATA.txt');
    theseLogPaths  = regexprep(theseOrgPaths,'\.cdf','-LOG.txt');
    
    thisBedPath  = fullfile(thisCrpDir,lsBed.name);
    thisWorkPath = fullfile(thisCrpDir,lsWork.name);
    
    croppedPaths{iSub1,1} = theseCrpPaths;
    dataPaths{iSub1,1}    = theseDataPaths;
    logPaths{iSub1,1}     = theseLogPaths;
    
    bedPaths{iSub1,1}  = thisBedPath;
    workPaths{iSub1,1} = thisWorkPath;
end

%% Iterate through subjects
h = waitbar(0,'Please wait. Converting subject data...');

nFile = numel(vertcat(croppedPaths{:}));
iFile = 1;
objArray = cell(nFile,1); % Preallocate storage for objects
for iSub2 = 1:nSub
    thisSub = subjects{iSub2};
    
    bedlogPath	= bedPaths{iSub2};
    bedlogExists = exist(bedlogPath,'file') == 2;
    
    for iSubFile = 1:numel(croppedPaths{iSub2})
        loginfoPath = logPaths{iSub2}{iSubFile};
        datalogPath	= dataPaths{iSub2}{iSubFile};
        cdfPath     = croppedPaths{iSub2}{iSubFile};
        
        loginfoExists = exist(loginfoPath,'file') == 2;
        datalogExists = exist(datalogPath,'file') == 2;
        cdfExists     = exist(cdfPath,'file') == 2;
        
        % Skip subjects missing files
        if ~all([loginfoExists, datalogExists, cdfExists, bedlogExists])
            warning(['Subject ',thisSub,' is missing files and was skipped.']);
            continue;
        end
        
        % Read data from CDF
        cdfData = daysimeter12.readcdf(cdfPath);
        
        % Create object
        thisObj = d12pack.HumanData;
        
        % Set calibration path
        thisObj.CalibrationPath = CalibrationPath;
        
        % Set ccalibration ratio method
        thisObj.RatioMethod = 'original+factor';
        thisObj.CorrectionFactor = 1.16;
        
        % Add subject ID
        thisObj.ID = thisSub;
        
        % Set time zones
        thisObj.TimeZoneLaunch = TimeZoneLaunch;
        thisObj.TimeZoneDeploy = TimeZoneDeploy;
        
        % Import the original data
        thisObj.log_info = thisObj.readloginfo(loginfoPath);
        thisObj.data_log = thisObj.readdatalog(datalogPath);
        
        % Correct for DST
        if ~isdst(thisObj.Time(1)) && isdst(thisObj.Time(end))
            idxDst = isdst(thisObj.Time);
            thisObj.Time(idxDst) = thisObj.Time(idxDst) - repmat(duration(1,0,0),size(thisObj.Time(idxDst)));
        end
        
        % Add observation mask (accounting for cdfread error)
        thisObj.Observation = false(size(thisObj.Time));
        tmpObservation = logical(cdfData.Variables.logicalArray);
        thisObj.Observation(1:numel(cdfData.Variables.logicalArray),1) = tmpObservation(:);
        
        % Add compliance mask (accounting for cdfread error)
        thisObj.Compliance = true(size(thisObj.Time));
        tmpCompliance = logical(cdfData.Variables.complianceArray);
        thisObj.Compliance(1:numel(cdfData.Variables.complianceArray),1) = tmpCompliance(:);
        
        % Add bed log
        thisObj.BedLog = thisObj.BedLog.import(bedlogPath);
        
        objArray{iFile,1} = thisObj;
        
        iFile = iFile + 1;
    end
    waitbar(iSub2/nSub);
end
close(h)

idxEmpty = cellfun(@isempty,objArray);
objArray(idxEmpty) = [];
objArray = vertcat(objArray{:});

fileName = ['data snapshot ',datestr(now,'yyyy-mmm-dd HH-MM'),'.mat'];
filePath = fullfile(projectDir,fileName);
save(filePath,'objArray');
end


