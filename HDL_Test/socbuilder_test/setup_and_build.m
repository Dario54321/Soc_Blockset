function setup_and_build(projectFolder, buildType)
%SETUP_AND_BUILD Applica i 3 fix del toolchain ARM e lancia socModelBuilder.
%
%   setup_and_build(projectFolder, buildType) esegue, in ordine:
%     1) rende visibile a MATLAB il compilatore Linaro ARM già scaricato
%        (codertarget.zynq.internal.addCompilerPath)
%     2) corregge il bug generico di MATLAB su Windows per cui system()/dos()
%        non cerca eseguibili nella cartella corrente (aggiunge "." al PATH)
%     3) copia iio.h nella cartella dove il buildInfo generato lo cerca,
%        se manca (fix one-time, persiste tra le sessioni)
%   poi lancia socModelBuilder/buildModel su 'Prova_1_socbuilder' con
%   BuildType=buildType (default 'Processor only').
%
%   projectFolder deve essere un percorso SENZA spazi (limite di
%   socModelBuilder), es. 'D:\SocBuilderBuild\soc_prj'.
%
%   Vedi docs/socbuilder_notes.md nel repository per la spiegazione
%   completa di ciascun fix (causa reale, non solo il workaround).

if nargin < 2
    buildType = 'Processor only';
end
if nargin < 1
    error('setup_and_build:missingArg', 'Specificare projectFolder (percorso senza spazi).');
end

% Fix 1: compilatore ARM Linaro visibile a MATLAB
codertarget.zynq.internal.addCompilerPath('6.3.1', 'AARCH32');
fprintf('Compiler path: %s\n', getenv('LINARO_TOOLCHAIN_6_3_1_AARCH32'));

% Fix 2: system()/dos() di MATLAB non cerca nella cartella corrente
if ~contains(getenv('PATH'), '.;')
    setenv('PATH', ['.;' getenv('PATH')]);
end

% Fix 3: iio.h mancante nella cartella attesa dal buildInfo generato
[~, matlabRelease] = fileparts(matlabroot); % es. 'R2023b'
expectedIioH = fullfile(getenv('ProgramData'), 'MATLAB', 'SupportPackages', ...
    matlabRelease, 'toolbox', 'shared', 'libiio', 'base', 'include', 'iio.h');
sourceIioH = matlab.internal.get3pInstallLocation('libiio.instrset');
if ~isempty(sourceIioH)
    sourceIioH = fullfile(sourceIioH, 'win64', 'include', 'iio.h');
end
if ~isempty(sourceIioH) && exist(sourceIioH, 'file') && ~exist(expectedIioH, 'file')
    copyfile(sourceIioH, expectedIioH);
    fprintf('Copiato iio.h in: %s\n', expectedIioH);
end

% Build vero e proprio
obj = socModelBuilder('Prova_1_socbuilder', 'ProjectFolder', projectFolder, 'BuildType', buildType);
buildModel(obj);
disp('setup_and_build: BUILD COMPLETATA CON SUCCESSO');

end
