function [boardName, fcnHandle] = registerPynqZ1
boardName = 'Pynq-Z1';
fcnHandle = @esb.internal.io.ConnectionToPynqZ1;
end
