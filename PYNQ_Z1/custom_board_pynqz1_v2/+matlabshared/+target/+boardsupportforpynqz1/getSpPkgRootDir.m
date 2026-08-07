function out = getSpPkgRootDir()
currfilepath = mfilename('fullpath');
out = fileparts(fileparts(fileparts(fileparts(currfilepath))));
end
