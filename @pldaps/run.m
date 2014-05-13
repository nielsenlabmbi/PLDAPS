function dv = run(dv)
% [dv] = run()
% PLDAPS (Plexon Datapixx PsychToolbox) version 4
%       run is a wrapper for calling PLDAPS condition files
%           It opens PsychImaging pipeline and initializes datapixx for
%           dual color lookup tables. Everything else must be in the
%           condition file and trial function. See PLDAPScheck.m for
%           explanation.  IMPORTANT: edit setupPLDAPSenv.m and
%           makeRigConfigFile.m before running. 
% INPUTS:
%       subj [string]       - initials for subject
%       condition [string]  - name of matlab function that runs trials
%                           - you must have the condition file in your path 
%       newsession [0 or 1] - if 1, start new PDS. 0 load old PDS (defaults
%       to 1)
%       [brackets] indicate optional variables and their default values

% 10/2011 jly wrote it (modified from letsgorun.m)
% 12/2013 jly reboot. updated to version 3 format.
% 04/2014 jk  movied into a pldaps classed; adapated to new class structure

% Tested to run with Psychtoolbox
% 3.0.11 - Flavor: beta - Corresponds to SVN Revision 4331
% For more info visit:
% https://github.com/Psychtoolbox-3/Psychtoolbox-3

%TODO: change edit setupPLDAPSenv.m and  makeRigConfigFile.m before running. 
% shoudl the outputfile uigetfile be optional?
% one same system for modules, e.g. moduleSetup, moduleUpdate, moduleClose
% make HideCursor optional
% make wait for return optional?
% TODO:reset class at end of experiment or mark as recorded, so I don't
% run the same again by mistake
% Todo save: defaultparameters beofre 1st trial

try
    %% Setup and File management
    % Enure we have an experimentSetupFile set and verify output file
    
    
    % pick YOUR experiment's main CONDITION file-- this is where all
    % expt-specific stuff emerges from
    if isempty(dv.defaultParameters.session.experimentSetupFile)
        [cfile, cpath] = uigetfile('*.m', 'choose condition file', [base '/CONDITION/debugcondition.m']); %#ok<NASGU>
        
        dotm = strfind(cfile, '.m');
        if ~isempty(dotm)
            cfile(dotm:end) = [];
        end
        dv.defaultParameters.session.experimentSetupFile = cfile;
    end
             
    dv.defaultParameters.session.initTime=now;
        
        
    if ~dv.defaultParameters.pldaps.nosave
        dv.defaultParameters.session.file = fullfile(dv.defaultParameters.pldaps.dirs.data, [dv.defaultParameters.session.subject datestr(dv.defaultParameters.session.initTime, 'yyyymmdd') dv.defaultParameters.session.experimentSetupFile datestr(dv.defaultParameters.session.initTime, 'HHMM') '.PDS']);
        [cfile, cdir] = uiputfile('.PDS', 'initialize experiment file', dv.defaultParameters.session.file);
        dv.defaultParameters.session.dir = cdir;
        dv.defaultParameters.session.file = cfile;
    else
        dv.defaultParameters.session.file='';
        dv.defaultParameters.session.dir='';
    end
        
    %% Open PLDAPS windows
    % Open PsychToolbox Screen
    dv = openScreen(dv);
    
    % Setup PLDAPS experiment condition
    dv = feval(dv.defaultParameters.session.experimentSetupFile, dv);
    
            %things that were in the conditionFile
            dv = eyelinkSetup(dv);
    
            %things that where in the default Trial Structure
            
            % Audio
            %-------------------------------------------------------------------------%
            dv = audioSetup(dv);
            
            % Audio
            %-------------------------------------------------------------------------%
            dv = spikeserverConnect(dv);
            
            % From help PsychDataPixx:
            % Timestamping is disabled by default (mode == 0), as it incurs a bit of
            % computational overhead to acquire and log timestamps, typically up to 2-3
            % msecs of extra time per 'Flip' command.
            % Buffer is collected at the end of the expeiment!
            PsychDataPixx('LogOnsetTimestamps', 2);%2
            PsychDataPixx('ClearTimestampLog');
            
    
            % Initialize Datapixx for Dual CLUTS
            dv = datapixxInit(dv);
            
            pdsKeyboardSetup();
    

    %% Last chance to check variables
%     dv  %#ok<NOPRT>
%     disp('Ready to begin trials. Type return to start first trial...')
%     keyboard %#ok<MCKBD>
    
 
    %%%%start recoding on all controlled components this in not currently done here
    % save timing info from all controlled components (datapixx, eyelink, this pc)
    dv = beginExperiment(dv);

    % disable keyboard
    ListenChar(2)
    HideCursor
    
    trialNr=1;
    
    %we'll have a trialNr counter that the trial function can tamper with?
    %do we need to lock the defaultParameters to prevent tampering there?
    levelsPreTrials=dv.defaultParameters.getAllLevels();
    dv.defaultParameters.addLevels(dv.conditions(trialNr), {['Trial' num2str(trialNr) 'Parameters']});
    
    %for now all structs will be in the parameters class, first
    %levelsPreTrials, then we'll add the condition struct before each trial.
    dv.defaultParameters.setLevels([levelsPreTrials length(levelsPreTrials)+trialNr])
    dv.defaultParameters.pldaps.iTrial=trialNr;
    dv.trial=dv.defaultParameters.mergeToSingleStruct();
    
    %only use dv.trial from here on!
    
    %% main trial loop %%
    while dv.trial.pldaps.iTrial <= dv.trial.pldaps.finish && dv.trial.pldaps.quit~=2
        
        if dv.trial.pldaps.quit == 0
            
            % run trial
            dv = feval(dv.trial.pldaps.trialFunction,  dv);
            
            
           result = saveTempFile(dv); 
           if ~isempty(result)
               disp(result.message)
           end
           
           
           
           %get the difference of the trial struct:
           dTrialStruct=dv.defaultParameters.getDifferenceFromStruct(dv.trial);
           dv.data{trialNr}=dTrialStruct;
           
           %advance to next trial
           trialNr=trialNr+1;
           if(dv.trial.pldaps.iTrial ~= dv.trial.pldaps.finish)
                %now we add this and the next Trials condition parameters
                dv.defaultParameters.addLevels(dv.conditions(trialNr), {['Trial' num2str(trialNr) 'Parameters']},[levelsPreTrials length(levelsPreTrials)+trialNr]);
                dv.defaultParameters.pldaps.iTrial=trialNr;
                dv.trial=dv.defaultParameters.mergeToSingleStruct();
           else
                dv.trial.pldaps.iTrial=trialNr;
           end
            
        else %dbquit ==1 is meant to be pause. should be halt eyelink, datapixx, etc?
            ListenChar(0);
            ShowCursor;
            keyboard %#ok<MCKBD>
            dv.quit = 0;
            ListenChar(2);
            HideCursor;
            
            
            datapixxRefresh(dv);
            
        end
        
    end
    
    %make the session parameterStruct active
    dv.defaultParameters.setLevels(levelsPreTrials);
    dv.trial = dv.defaultParameters;
    
    % return cursor and command-line control
    ShowCursor
    ListenChar(0)
    Priority(0)
    
    dv = eyelinkFinish(dv);
    dv = spikeserverDisconnect(dv);
    if(dv.defaultParameters.datapixx.use)
        dv.defaultParameters.datapixx.timestamplog = PsychDataPixx('GetTimestampLog', 1);
    end
    
    
    if ~dv.defaultParameters.pldaps.nosave
        [structs,structNames] = dv.defaultParameters.getAllStructs();
        
        PDS=struct;
        PDS.initialParameters=structs(levelsPreTrials);
        PDS.initialParameterNames=structNames(levelsPreTrials);
        PDS.conditions=structs((max(levelsPreTrials)+1):end);
        PDS.conditionNames=structNames((max(levelsPreTrials)+1):end);
        PDS.data=dv.data; %#ok<STRNU>
        save(fullfile(dv.defaultParameters.session.dir, dv.defaultParameters.session.file),'PDS','-mat')
    end
    
    
    Screen('CloseAll');
    sca
    
    
catch me
    sca
    
    % return cursor and command-line cont[rol
    ShowCursor
    ListenChar(0)
    disp(me.message)
    
    nErr = size(me.stack); 
    for iErr = 1:nErr
        fprintf('errors in %s line %d\r', me.stack(iErr).name, me.stack(iErr).line)
    end
    fprintf('\r\r')
    keyboard    
end
