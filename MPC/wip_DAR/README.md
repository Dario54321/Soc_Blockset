# wip_DAR

Area di lavoro di Dario dentro [`MPC/`](../README.md). Non integrato: quando
qualcosa qui è stabile, si promuove a `MPC/` (root).

## `main_Controller_NMPC.m`

Copia di lavoro di [`MPC_Emanuele/main_Controller_NMPC.m`](../MPC_Emanuele/main_Controller_NMPC.m),
con solo due modifiche rispetto all'originale (che resta intatto):
`addpath` verso `MPC_Emanuele/` e `DataDir` valorizzato (era il punto che il
README di Emanuele segnala come obbligatorio, riga 45 dell'originale).

**Non ancora eseguibile**: `load_system('CAccEma_v3_NMPC_ARM_2023b')` fallisce
perché quel modello Simulink non è nel repo di Emanuele — va richiesto a lui.
Finché non arriva, questo file resta pronto ma bloccato lì.
