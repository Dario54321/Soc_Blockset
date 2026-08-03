% This script initializes the CACC example model. It loads necessary control
% constants, buses adn scenario files required for the referenced model
%
% Copia di lavoro di MPC_Emanuele/main_Controller_NMPC.m, autonoma (tutti i
% file richiamati sono copie locali con suffisso _Test, per evitare conflitti
% di nome/path con l'originale in MPC_Emanuele/ quando entrambe le cartelle
% sono sul path di MATLAB). L'originale in MPC_Emanuele/ non va toccato.
%
% Modifiche rispetto all'originale:
%   1. DataDir punta alla copia locale di Traces For Git (riga 45
%      dell'originale, valore obbligatorio per il README di Emanuele).
%   2. Chiama GPCADMM_NL_Setup_Test (non GPCADMM_NL_Setup) e carica
%      TestBenchPar_NL_Test.mat (non l'originale).
%   3. Il wrapping Simulink.Parameter di Np/Nc è spostato DOPO
%      GPCADMM_NL_Setup_Test (che vuole Np/Nc come numeri semplici — bug
%      segnalato a Emanuele, non ancora corretto a monte al 2026-08-03).
%      Gli oggetti risultanti si chiamano ANCORA Np/Nc (non NpParam/NcParam
%      come in un tentativo precedente): verificato aprendo
%      CAccEma_v3_NMPC_MPSoC_2023b_Test.slx (è uno zip, ispezionato l'XML)
%      che due Stateflow chart hanno dati "PARAMETER_DATA" chiamati
%      esattamente Np/Nc, inizializzati dal workspace base per nome — un
%      nome diverso non verrebbe trovato dal modello.

clear, bdclose('all'), clc,

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);

%% Test Bench parameters
load TestBenchPar_NL_Test.mat
% Ts value
Ts = 0.01;
NpRange = 15:5:35;
% for i = 1:numel(NpRange)
i = numel(NpRange);
% Np value (numero semplice: GPCADMM_NL_Setup_Test fa N2=Np, N2*0.1 — non
% regge un Simulink.Parameter, vedi bug segnalato a Emanuele)
Np = NpRange(i);
Nc = 3;   % GPCADMM_NL_Setup_Test lo ricalcola comunque (vedi confronto_paper_vs_MPC_Emanuele.md §4.3)

NpStr = num2str(Np);
NpType = regexprep(NpStr,'\.','');

GPCADMM_NL_Setup_Test
% Da qui in poi Np/Nc sono ancora numeri semplici (GPCADMM_NL_Setup_Test li
% ricalcola ma non li ri-wrappa) — catturo i valori prima di convertirli.
NpValue = Np;
NcValue = Nc;

%% Esposizione a Simulink come parametri tunabili (dopo il setup, non prima)
% Nomi ANCORA Np/Nc: il modello li cerca per nome esatto nel workspace base
% (Stateflow PARAMETER_DATA, verificato nell'XML del .slx).
Np = Simulink.Parameter;
Np.Value = NpValue;
Np.CoderInfo.StorageClass = 'Auto';

Nc = Simulink.Parameter;
Nc.Value = NcValue;
Nc.CoderInfo.StorageClass = 'Auto';

%% STEP 1: Impostazioni di base
model = 'CAccEma_v3_NMPC_MPSoC_2023b_Test';        % Controller model (copia locale)

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

DataDir = fullfile(scriptDir, 'Traces For Git');

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
