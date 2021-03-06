%% Confidence experiment
%
% Runs one session of the confidence experiment.
%
PsychPortAudio('Close');

sca; clear;
%% Global parameters.
rng('shuffle')
setup;
if strcmp(options.do_trigger, 'yes')
    addpath matlabtrigger/
else
    addpath faketrigger/
end
%% Setup the ParPort
trigger_enc = setup_trigger;
%setup_parport;

%% Parameters that control appearance of the gabors that are constant over
% trials
opts = {'num_cycles', 5,...
    'duration', .1,...
    'ppd', options.ppd,...%31.9,... % for MEG display at 65cm viewing distance
    'xpos', [-10, 10],...
    'ypos', [6.5, 6.5]}; % Position Gabors in the lower hemifield to get activation in the dorsal pathaway



try
    %% Ask for some subject details and load old QUEST parameters
    subject.initials = input('Initials? ', 's');
    if str2num(subject.initials(2:3)) > 8
        fprintf('Subject ID>8, assuming left second, right first\n');
        subject.mapping = 2;
    elseif str2num(subject.initials(2:3)) <= 8
        fprintf('Subject ID<=8, assuming left first, right second\n');
        subject.mapping = 1;
    else
        subject.mapping = 1;
    end
    
    options.datadir = fullfile(options.datadir, subject.initials);
    [~, ~, ~] = mkdir(options.datadir);
    quest_file = fullfile(options.datadir, 'quest_results.mat');
    session_struct = struct('q', [], 'results', [], 'date', datestr(clock));
    results_struct = session_struct;
    session_identifier =  datestr(now, 30);
    
    append_data = false;
    if exist(quest_file, 'file') == 2
        if strcmp(input('There is previous data for this subject. Load last QUEST parameters? [y/n] ', 's'), 'y')
            [~, results_struct, quest.threshold_guess, quest.threshold_guess_sigma] = load_subject(quest_file);
            append_data = true;
        end
    end
    
    
    
    %% Configure Psychtoolbox
    setup_ptb;
    
    Screen('FillRect', window, [.5, .5, .5]);
    Screen('Flip', window);
    % start recording eye position
    Eyelink('StartRecording');
    % record a few samples before we actually start displaying
    WaitSecs(0.1);
    % mark zero-plot time in data file
    Eyelink('message', 'Start recording Eyelink');
    
    %% Set up QUEST
    q = QuestCreate(quest.threshold_guess, quest.threshold_guess_sigma, quest.pThreshold, quest.beta, quest.delta, quest.gamma);
    q.updatePdf = 1;
    
    % A structure to save results.
    results = struct('response', [], 'side', [], 'choice_rt', [], 'correct', [],...
        'contrast', [], 'contrast_probe', [], 'contrast_ref', [],...
        'confidence', [], 'repeat', [], 'repeated_stim', [], 'session', [], 'noise_sigma', [], 'expand', []);
    
    % Sometimes we want to repeat the same contrast fluctuations, load them
    % here. You also need to set the repeat interval manually. The repeat
    % interval specifies the interval between repeated contrast levels.
    % If you want to show each of, e.g. 5 repeats twice and you have 100
    % trials, set it to 10.
    options.repeat_contrast_levels = 0;
    if options.repeat_contrast_levels
        contrast_file_name = fullfile(options.datadir, 'repeat_contrast_levels.mat');
        repeat_levels = load(contrast_file_name, 'levels');
        repeat_levels = repeat_levels.levels;
        % I assume that repeat_contrast_levels contains a struct array with
        % fields contrast_a and contrast_b.
        assert(options.num_trials > length(repeat_levels));
        repeat_interval = 2; %'Replace with a sane value'; % <-- Set me!
        repeat_counter = 1;
    end
    %% Do Experiment
    for trial = 1:10
        try
            % This supplies the title at the bottom of the eyetracker display
            Eyelink('command', 'record_status_message "TRIAL %d/%d"', trial, options.num_trials);
            Eyelink('message', 'TRIALID %d', trial);
            
            repeat_trial = false;
            repeated_stim = nan;
            
            % Sample contrasts.
            %contrast = min(1, max(0, (QuestQuantile(q, 0.5))));
            contrast = 0.25;
            side = randsample([1,-1], 1);
            ns  = randsample([1, 2, 3], 1);
            noise_sigma = options.noise_sigmas(ns);
            [side, contrast_fluctuations, eff_noise] = sample_contrast(side, contrast,...
                noise_sigma, options.baseline_contrast); % Converts effective contrast to absolute contrst
            expand = randsample([-1, 1], 1);
            fprintf('Correct is: %i, mean contrast is %f\n', side, mean(contrast_fluctuations))
            % Set options that are valid only for this trial.
            trial_options = [opts, {...
                'contrast_probe', contrast_fluctuations,...
                'contrast_ref', options.baseline_contrast,...
                'baseline_delay', 3 + rand*0.5,...
                'inter_stimulus_delay', 1 + rand*0.5,...
                'feedback_delay', 0.5 + rand*1,...
                'rest_delay', 0.5,...
                'ringwidth', options.ringwidth,...
                'radius', options.radius,...
                'inner_annulus', options.inner_annulus,...
                'sigma', options.sigma,...
                'cutoff', options.cutoff,...
                'expand', expand,...
                'kbqdev', options.kbqdev}];
            
            % Encode trial number in triggers.
            bstr = dec2bin(trial, 8);
            pins = find(str2num(reshape(bstr',[],1))');
            WaitSecs(0.005);
            for pin = pins
                trigger(pin);
                WaitSecs(0.005);
            end
            [correct, response, confidence, rt_choice, timing] = one_trial(window, options.window_rect, screenNumber,...
                subject.mapping, side, ns, ringtex, audio,  trigger_enc, options.beeps, options.ppd, trial_options);
            
            timings{trial} = timing;
            %if ~isnan(correct) && ~repeat_trial
            %q = QuestUpdate(q, contrast + mean(eff_noise), correct);
            %end
            results(trial) = struct('response', response, 'side', side, 'choice_rt', rt_choice, 'correct', correct,...
                'contrast', contrast, 'contrast_probe', contrast_fluctuations, 'contrast_ref', options.baseline_contrast,...
                'confidence', confidence, 'repeat', repeat_trial, 'repeated_stim', repeated_stim,...
                'session', session_identifier, 'noise_sigma', noise_sigma, 'expand', expand);
            Eyelink('message', 'TRIALEND %d', trial);
        catch ME
            if (strcmp(ME.identifier,'EXP:Quit'))
                break
            else
                rethrow(ME);
            end
        end
    end
catch ME
    if (strcmp(ME.identifier,'EXP:Quit'))
        return
    else
        disp(getReport(ME,'extended'));
        Eyelink('StopRecording');
        PsychPortAudio('Stop');
        PsychPortAudio('Close');
        rethrow(ME);
    end
end
Eyelink('StopRecording');

LoadIdentityClut(window);
sca
fprintf('Saving data to %s\n', options.datadir)
eyefilename   = fullfile(options.datadir, sprintf('intro_%s_%s.edf', subject.initials, session_identifier));
Eyelink('CloseFile');
Eyelink('WaitForModeReady', 500);
try
    status = Eyelink('ReceiveFile', options.edfFile, eyefilename);
    disp(['File ' eyefilename ' saved to disk']);
catch
    warning(['File ' eyefilename ' not saved to disk']);
end

Eyelink('StopRecording');
PsychPortAudio('Close');
session_struct.q = q;
%session_struct.results = struct2table(results);
session_struct.results = results;

save( fullfile(options.datadir, sprintf('intro_%s_%s_results.mat', subject.initials, datestr(clock))), 'session_struct')
if ~append_data
    results_struct = session_struct;
else
    disp('Trying to append')
    results_struct(length(results_struct)+1) = session_struct;
end
%save(fullfile(options.datadir, 'quest_results.mat'), 'results_struct')
%writetable(session_struct.results, fullfile(datadir, sprintf('%s_%s_results.csv', initials, datestr(clock))));
