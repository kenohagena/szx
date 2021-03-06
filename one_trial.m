function [correct, response, confidence, rt_choice, timing] = one_trial(window, windowRect, screen_number, mapping, correct_location, ns, ringtex, pahandle, trigger_enc, beeps, ppd, variable_arguments)
%% function [correct, response, confidence, rt_choice, rt_conf] = one_trial(window, windowRect, screen_number, correct_location, gabortex, gaborDimPix, pahandle, variable_arguments)
%
% Presents a circular contracting/expanding grating with a reference
% contrast, then the same with changing contrast. Ask for response and
% confidence.
%
% Parameters
% ----------
%
% window : window handle to draw into
% windowRect : dimension of the window
% screen_number : which screen to use
% correct_location : -1 if correct is right, 1 if left
% ringtex : the ring texture to draw
% pahandle : audio handle
%
% Variable Arguments
% ------------------
%
% ringwidth : spatial frequency of the grating
% contrast_reference : contrast of the reference
% contrast_probe : array of contrast values for the probe stimulus
% driftspeed : how fast the gabors drift (units not clear yet)
% ppd : pixels per degree to convert to visual angles
% duration : how long each contrast level is shown in seconds
% baseline_delay : delay between trial start and stimulus onset.
% feedback_delay : delay between confidence response and feedback onset
% rest_delay : delay between feedback onset and trial end



%% Process variable input stuff
ref_duration =  default_arguments(variable_arguments, 'ref_duration', .400);
radius = default_arguments(variable_arguments, 'radius', 150);
inner_annulus = default_arguments(variable_arguments, 'inner_annulus', 5);
ringwidth = default_arguments(variable_arguments, 'ringwidth', 25);
sigma = default_arguments(variable_arguments, 'sigma', 2*ppd);
cutoff = default_arguments(variable_arguments, 'cutoff', 2*ppd);

contrast_reference = default_arguments(variable_arguments, 'contrast_reference', 0.5);
contrast_probe = default_arguments(variable_arguments, 'contrast_probe', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]/10.);
driftspeed = default_arguments(variable_arguments, 'driftspeed', 1);
duration = default_arguments(variable_arguments, 'duration', .5);
baseline_delay = default_arguments(variable_arguments, 'baseline_delay', 0.5);
inter_stimulus_delay = default_arguments(variable_arguments, 'inter_stimulus_delay', 0.5);
decision_delay = default_arguments(variable_arguments, 'decision_delay', 0.0);
feedback_delay = default_arguments(variable_arguments, 'feedback_delay', 0.5);
rest_delay = default_arguments(variable_arguments, 'rest_delay', 0.5);
expand = default_arguments(variable_arguments, 'expand', 1);
kbqdev = default_arguments(variable_arguments, 'kbqdev', []);


%% Setting the stage
timing = struct();
if mapping == 1
    first_conf_high = {'1', '1!'};
    first_conf_low = {'2', '2@'};
    second_conf_low = {'3', '3#'};
    second_conf_high = {'4', '4$'};
elseif mapping == 2
    first_conf_high = {'4', '4$'};
    first_conf_low = {'3', '3#'};
    second_conf_low = {'2', '2@'};
    second_conf_high = {'1', '1!'};
else
 throw(MException('Id:UserError','Mapping not recognized'));    
end

quit = 'ESCAPE';

black = BlackIndex(screen_number);

[xCenter, yCenter] = RectCenter(windowRect);
ifi = Screen('GetFlipInterval', window);


%% Baseline Delay period

% Draw the fixation point
Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);
vbl = Screen('Flip', window);
timing.TrialOnset = vbl;

trigger(trigger_enc.trial_start);
WaitSecs(0.005);
if correct_location == -1
    trigger(trigger_enc.stim_strong_right); % Ref correct
elseif correct_location == 1
    trigger(trigger_enc.stim_strong_left);
end
WaitSecs(0.005);
trigger(trigger_enc.noise_sigma + ns);
WaitSecs(0.001);
waitframes = (baseline_delay-0.01)/ifi;

flush_kbqueues(kbqdev);


%% Show reference
[low, high] = contrast_colors(contrast_reference, 0.5);
shiftvalue = 0;
for frame = 1:(ref_duration/ifi)
    Screen('DrawTexture', window, ringtex, [], [], [], [], [], low, [], [],...
        [high(1), high(2), high(3), high(4), shiftvalue, ringwidth, radius, inner_annulus, sigma, cutoff, xCenter, yCenter]);
    Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);

    vbl = Screen('Flip', window, vbl + (waitframes-0.1) * ifi);
    if frame == 1
        timing.ref_onset = vbl;
        trigger(trigger_enc.stim_onset);
    end
    waitframes = 1;
    shiftvalue = shiftvalue+expand*driftspeed;
end
Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);
vbl = Screen('Flip', window);
timing.ref_offset = vbl;
trigger(trigger_enc.stim_off );

waitframes = (inter_stimulus_delay-0.01)/ifi;

%% Animation loop
start = nan;
cnt = 1;
framenum = 1;
dynamic = [];
stimulus_onset = nan;
[low, high] = contrast_colors(contrast_probe(cnt), 0.5);
%cnt = cnt+1;
while ~((GetSecs - stimulus_onset) >= (length(contrast_probe))*duration-2*ifi) 
    
    % Set the right blend function for drawing the gabors
    Screen('BlendFunction', window, 'GL_ONE', 'GL_ZERO');
    %Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');

    Screen('DrawTexture', window, ringtex, [], [], [], [], [], low, [], [],...
        [high(1), high(2), high(3), high(4), shiftvalue, ringwidth, radius, inner_annulus, sigma, cutoff, xCenter, yCenter]);
    shiftvalue = shiftvalue+expand*driftspeed;
    % Change the blend function to draw an antialiased fixation point
    % in the centre of the array
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    
    % Draw the fixation point
    Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);
    
    % Flip our drawing to the screen
    vbl = Screen('Flip', window, vbl + (waitframes-.5) * ifi);
    flush_kbqueues(kbqdev);

    if framenum == 1
        Eyelink('message', 'SYNCTIME');
        trigger(trigger_enc.stim_onset);
        WaitSecs(0.001);
    end
    framenum = framenum +1;
    waitframes = 1;
    dynamic = [dynamic vbl];
    
    % Change contrast every 100ms
    elapsed = GetSecs;
    if isnan(start)
        stimulus_onset = GetSecs;
        Eyelink('message', sprintf('conrast %f',contrast_probe(cnt)));
        trigger(trigger_enc.con_change);
        start = GetSecs;
    end
    if (elapsed-start) > (duration-.5*ifi)
        start = GetSecs;        
        cnt = cnt+1;
        [low, high] = contrast_colors(contrast_probe(cnt), 0.5);        
        trigger(trigger_enc.con_change);
        Eyelink('message', sprintf('conrast %f',contrast_probe(cnt)));

    end
    
end

target = (waitframes - 0.5) * ifi;
Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
timing.animation = dynamic;

%%% Get choice
% Draw the fixation point
Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);
vbl = Screen('Flip', window, vbl + target );

trigger(trigger_enc.decision_start);
Eyelink('message', 'decision_start 1');

timing.response_cue = vbl;
start = GetSecs;
rt_choice = nan;
key_pressed = false;
error = false;
response = nan;
RT = nan;
while (GetSecs-start) < 2
    [keyIsDown, firstPress] = check_kbqueues(kbqdev);
    if keyIsDown
        RT = GetSecs();
        keys = KbName(firstPress);
        if iscell(keys)
            error = true;
            break
        end
        switch keys
            case quit
                throw(MException('EXP:Quit', 'User request quit'));
            case first_conf_high
                Eyelink('message', sprintf('decision %i', trigger_enc.first_conf_high))
                trigger(trigger_enc.first_conf_high);
                response = -1;
                confidence = 2;
            case first_conf_low
                Eyelink('message', sprintf('decision %i', trigger_enc.first_conf_low))
                trigger(trigger_enc.first_conf_low);
                response = -1;  
                confidence = 1;
            case second_conf_low
                Eyelink('message', sprintf('decision %i', trigger_enc.second_conf_low))
                trigger(trigger_enc.second_conf_low);
                response = 1;                
                confidence = 1;
            case second_conf_high
                Eyelink('message', sprintf('decision %i', trigger_enc.second_conf_high));
                trigger(trigger_enc.second_conf_high);
                response = 1;
                confidence = 2;                
        end
        if ~isnan(response)
            if correct_location == response
                correct = 1;
                fprintf('Choice Correct\n')
            else
                correct = 0;
                fprintf('Choice Wrong\n')
            end
            rt_choice = RT-start;
            key_pressed = true;
            break;
        end
    end
end
timing.RT = RT;


if ~key_pressed || error
    trigger(trigger_enc.no_decisions);
    Eyelink('message', 'decision 88');
    fprintf('Error in answer\n')
    wait_period = 1 + feedback_delay + rest_delay;
    WaitSecs(wait_period);
    correct = nan;
    response = nan;
    confidence = nan;
    rt_choice = nan;
    trigger(trigger_enc.trial_end);
    return
end



%% Provide Feedback
beep = beeps{correct+1};
PsychPortAudio('FillBuffer', pahandle.h, beep);
timing.feedback_delay_start = vbl;
Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);
waitframes = (feedback_delay/ifi) - 1;
vbl = Screen('Flip', window, vbl + (waitframes - 0.5) * ifi);
t1 = PsychPortAudio('Start', pahandle.h, 1, 0, 1);
if correct
    trigger(trigger_enc.feedback_correct);
    Eyelink('message', 'feedback 1');
else
    trigger(trigger_enc.feedback_incorrect);
    Eyelink('message', 'feedback -1');
end
timing.feedback_start = t1;

Screen('DrawDots', window, [xCenter; yCenter], 10, black, [], 1);
waitframes = rest_delay/ifi;
vbl = Screen('Flip', window, t1 + (waitframes - 0.5) * ifi);
timing.trial_end = vbl;
trigger(trigger_enc.trial_end);