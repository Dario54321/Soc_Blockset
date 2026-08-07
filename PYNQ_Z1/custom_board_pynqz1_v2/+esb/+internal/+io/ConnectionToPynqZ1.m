classdef ConnectionToPynqZ1 < soc.internal.zynq
methods (Access = protected)
function updateBoardName(obj)
obj.BoardName = 'Pynq-Z1';
end
end
end
