% This script initializes the CACC example model. It loads necessary control
% constants, buses adn scenario files required for the referenced model
%
% Copia di lavoro di MPC_Emanuele/main_Controller_NMPC.m: l'originale non va
% toccato (vedi MPC_Emanuele/PROVENIENZA.md). Modifiche rispetto
% all'originale:
%   1. addpath verso MPC_Emanuele/ e DataDir valorizzato (riga 45
%      dell'originale, segnalata come obbligatoria dal README di Emanuele).
%   2. Il wrapping Simulink.Parameter di Np/Nc è spostato DOPO
%      GPCADMM_NL_Setup (che vuole Np/Nc come numeri semplici — vedi bug
%      segnalato a Emanuele, non ancora corretto nel suo repo al 2026-08-03).
%      Gli oggetti Simulink.Parameter si chiamano ora NpParam/NcParam: se il
%      modello si aspetta variabili chiamate esattamente Np/Nc in workspace,
%      vanno rinominate di nuovo — da verificare aprendo il modello.

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
% Np value (numero semplice: GPCADMM_NL_Setup fa N2=Np, N2*0.1 — non regge un
% Simulink.Parameter, vedi bug segnalato a Emanuele)
Np = NpRange(i);
Nc = 3;   % GPCADMM_NL_Setup lo ricalcola comunque (vedi §4.3 del confronto)

NpStr = num2str(Np);
NpType = regexprep(NpStr,'\.','');

GPCADMM_NL_Setup

%% Esposizione a Simulink come parametri tunabili (dopo il setup, non prima)
NpParam = Simulink.Parameter;
NpParam.Value = Np;
NpParam.CoderInfo.StorageClass = 'Auto';

NcParam = Simulink.Parameter;
NcParam.Value = Nc;
NcParam.CoderInfo.StorageClass = 'Auto';

%% STEP 1: Impostazioni di base
model = 'CAccEma_v3_NMPC_MPSoC_2023b';        % Controller model
% Rinominato da Emanuele (era 'CAccEma_v3_NMPC_ARM_2023b'), ora presente in
% MPC_Emanuele/.

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
