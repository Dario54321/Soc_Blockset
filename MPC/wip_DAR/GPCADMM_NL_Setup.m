% Setup Offline GPCADMM
% clear, clc
%% Load Parameters
load('TestBenchPar_NL.mat');
m_ass = m_ego; % mass car, [Kg]
tau = 0.1;

%% scaling operation
s_u = 400; % scaling actuation factor (Max Torqu)

%% MPC control parameters
sampling_time = Ts; % Sampling time [s]
N1 = 1; 
N2 = Np.Value; 
if N2*0.1 <= 5
    Nc = 5;
else
    Nc = N2*0.1;
end
Np = N2 - N1 + 1; 

Q_delta_diag = repmat([1; 400; 0.1], Np, 1); % Weight matrix on state error. more weight on position error
Q_delta = diag(Q_delta_diag);

R_lambda_diag = repmat(100, Nc, 1); % weight matrix on actuation signal
R_lambda = diag(R_lambda_diag);

ny = 3; 
nu = 1; 

%% Constraints definition
% 1. Constraints on the variation of input signal
du_max_fisico = 50; % [Nm/step]
du_max = du_max_fisico / s_u; % Adimensionato

% 2. Constraint on input (Torque Max and Min)
u_max_fisico = 400; % [Nm]
u_max = u_max_fisico / s_u; % Sarà 1.0

u_min_fisico = -400; % [Nm]
u_min = u_min_fisico / s_u; % Sarà -1.0

% Constraints matrices: R_vincolo:
Tril_mat = tril(ones(Nc));   % lower triangular matrix
R_vincolo = [eye(Nc);       % 1. Max Delta_u
    -eye(Nc);       % 2. Min Delta_u
    Tril_mat;       % 3. u_max (Sum of delta_u)
    -Tril_mat];     % 4. u_min

% static blocks for r_vincolo
r_du_block = repmat(du_max, Nc, 1);

% Vettori statici per i limiti di input assoluti
r_u_max_static = repmat(u_max, Nc, 1);
r_u_min_static = repmat(u_min, Nc, 1); % Corretto: usa u_min!

% Vettore b dei vincoli (la logica matematica Ax <= b richiede -u_min)
r_acc_static = [r_u_max_static; -r_u_min_static]; 

% Solver parameter ADMM
rho = 1.0; 
N_iter = 20; 

I_ny = eye(ny);
M_rep = repmat(I_ny,Np,1);

%% Initial condition for online matrices
F_0 = zeros(Np * 3, 3);

G_0 = zeros(Np * 3, Nc * 1);