function [boardName, fcnHandle] = registerPynqZ1Test
boardName = 'Pynq-Z1';
fcnHandle = @esb.internal.io.ConnectionToPynqZ1Test;
end
