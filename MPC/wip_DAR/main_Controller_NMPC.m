% This script initializes the CACC example model. It loads necessary control
% constants, buses adn scenario files required for the referenced model
%
% Copia di lavoro di MPC_Emanuele/main_Controller_NMPC.m: l'originale non va
% toccato (vedi MPC_Emanuele/PROVENIENZA.md). Uniche modifiche rispetto
% all'originale: addpath verso MPC_Emanuele/ e DataDir valorizzato (riga 45
% del file originale, segnalata come obbligatoria dal README di Emanuele).

clear, bdclose('all'), clc,

scriptDir = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDir, '..', 'MPC_Emanuele'));

%% Test Bench parameters
load TestBenchPar_NL.mat
% Ts value
Ts = 0.01;
NpRange = 15:5:35;
% for i = 1:numel(NpRange)
i = numel(NpRange);
% Np value

Np = Simulink.Parameter;
Np.Value = NpRange(i);
Np.CoderInfo.StorageClass = 'Auto';

Nc = Simulink.Parameter;
Nc.Value = 3;
Nc.CoderInfo.StorageClass = 'Auto';

NpStr = num2str(Np.Value);
NpType = regexprep(NpStr,'\.','');

GPCADMM_NL_Setup

%% STEP 1: Impostazioni di base
model = 'CAccEma_v3_NMPC_ARM_2023b';        % Controller model
% NB: questo modello .slx non è nel repo di Emanuele — va richiesto a lui.
% Finché non c'è, questo script si ferma qui sotto (load_system fallisce).

% open_system(model);
load_system(model);

% configure model for MIL simulation
set_param(model, 'SimulationMode', 'normal');
save_system(model);
bdclose(model)

%% Load input data
% starting directory

% Save profilation data externally
FolderName = append('Np',NpType,'_folder');

DataDir = fullfile(scriptDir, '..', 'MPC_Emanuele', 'Traces For Git');

% Create the folder if it does not exist
if ~isfolder(DataDir)
    mkdir(DataDir);
end

% traces' matfiles
cd(DataDir);

%for the scenario, we iniliatize each folder for each value of a_cc
expNpFixed = dir('*ExpForPIL_Scenario*');
expNpFixedNames = {expNpFixed.name};
expNpFixedNames = char(expNpFixedNames);

% for j = 1:numel(expNpFixedNames(:,1))
j = 1;

%% Open and load model
% for each experiment in Np =* folder, we load the data and run a mil experiment

% open_system(model);
load_system(model);

%% Open test_list file & % Load test from test list
% extract prediction horizon from .mat name
NameProfData = expNpFixedNames(j,:);

Dumb1 = split(NameProfData,'_');

data = load(expNpFixedNames(j,:));

%% Timeseries acquisitions
ds = Simulink.SimulationData.Dataset;

ds = ds.addElement(data.LongVel_Follwr,'LongVel_Follwr');
ds = ds.addElement(data.PosErrFollwr1,'PosErrFollwr1');
ds = ds.addElement(data.VelErrFollwr1,'VelErrFollwr1');
ds = ds.addElement(data.V2V_BSM,'V2V_BSM');

simIn(j) = Simulink.SimulationInput(model);
simIn(j) = simIn(j).setModelParameter('SignalLogging','on');
% simIn(j) = simIn(j).setVariables('Np', 20);
simIn(j) = simIn(j).setVariable('indexJ',j);

% simIn(j) = simIn(j).setPreSimFcn(@upate_params_callback);

simIn(j) = simIn(j).setExternalInput(ds);


%% Init test
simOut = sim(simIn(j));

AccCmd = simOut.logsout.get('AccCmd') ;
Dumb3 = Dumb1{5};
save(append("AccCmdSingleOut_",Dumb3,".mat"),'AccCmd');
bdclose(model);

% end
save("ExSimSigDouble.mat","simIn")
cd ..
% end
% cd(DataDir)
