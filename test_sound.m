
clear
options.beeps = {repmat(audioread('low_mrk_150Hz.wav'), 1,2)', repmat(audioread('high_mrk_350Hz.wav'), 1,2)'};

InitializePsychSound(1);
devices = PsychPortAudio('GetDevices');


for i = 1:length(devices)
    if strncmp(devices(i).DeviceName, 'UA-25: USB Audio', 5)
%    if strncmp(devices(i).DeviceName,'UA-25: USB Audio', 16) %UA-25: USB Audio (hw:1,0)')
        break
    end
end

devices(i)

audio = [];

%i = 10; % for the EEG lab
audio.i = devices(i).DeviceIndex;
audio.freq = devices(i).DefaultSampleRate;
audio.device = devices(i);
audio.h = PsychPortAudio('Open',audio.i,1,1,audio.freq,2);
PsychPortAudio('RunMode',audio.h,1);

beep = options.beeps{1};
PsychPortAudio('FillBuffer', audio.h, beep);
t1 = PsychPortAudio('Start', audio.h, 1, 0, 1);
PsychPortAudio('Close');