function data = editSimData(data,address,target,fcn)
% editSimData Editor for Simulink Datasets
% 
% newdata = editSimData(data,address,target,fcn) looks for all timeseries
%   objects underneath the addressed object in "data" (the first input) and
%   executes the function passed by handle as "fcn" (the fourth input) on
%   the timeseries, its Time valuse, or its Data values as specified by
%   "target" (the third input).
% 
% Inputs:
% 
%   data = The data to be edited. Can be of type
%     Simulink.SimulationData.Dataset, Simulink.SimulationData.Signal,
%     struct, or timeseries. Can be an array of any one of these types in
%     which case the editing is done on each element of the array.
% 
%   address = A string specifying the top level object to edit within
%     "data." Specified using structure-like dot syntax. This syntax does
%     not depend on the type of "data." For example, if you would access a
%     data set with >> data.get('Signal2').Values.Subsignal3.timeseries1
%     "address" would take the value >> 'Signal2.Subsignal3.timeseries1'.
% 
%   target = '', 'Time', or 'Data'. This value determines what part of each
%     timeseries is input to the function handle "fcn." If "target" is
%     empty, the whole timeseries is passed to "fcn," otherwise it receives
%     the Time values or Data values according to the value of "target."
% 
%   fcn = A function handle whose first input is a timeseries, its Time, or
%     its Data, cnosistent with the specification in "target." editSimData
%     will replace all timeseries, their Times, or their Data, (again,
%     according to "target") with the result of "fcn."
% 
% Outputs:
% 
%   data = The revised version of the input "data." The output will have
%     the same type and structure as the input.
% 
% Examples:
% 
%   % Create a dataset on which to operate
%   A = Simulink.SimulationData.Dataset();
%   s = Simulink.SimulationData.Signal();
%   s.Name = 'Signal1';
%   t = linspace(0,2*pi,100);
%   s.Values.sin_t = timeseries(sin(t),t);
%   s.Values.cos_t = timeseries(cos(t),t);
%   A = A.addElement(s);
%   s.Name = 'Signal2';
%   A = A.addElement(s);
% 
%   % Shift all the times of Signal1 back by 1
%   B = editSimData(A,'Signal1','Time',@(time)time+1);
% 
%   % Scale all the values of Signal2 back by 2
%   C = editSimData(A,'Signal2','Data',@(data)data*2);
% 
%   % Resample all timeseries in x to newtime
%   newtime = linspace(1,2*pi,100);
%   D = editSimData([B,C],'','',@(ts)resample(ts,newtime));
% 
%   % View the results with viewSimData
%   viewSimData([A,B,C,D])
% 
% Created by:
%   Robert Perrotta

% Input validation
allowableClasses = {
    'Simulink.SimulationData.Dataset'
    'Simulink.SimulationData.Signal'
    'struct'
    'timeseries'
    };
assert(any(strcmp(class(data),allowableClasses)),...
    'Input "data" must be one of the following classes:\n%s',...
    sprintf('\t%s\n',allowableClasses{:}))
assert(isempty(target)|strcmp(target,'Time')|strcmp(target,'Data'),...
    'Input "target" must be empty, ''Time'', or ''Data''.')
assert(isa(fcn,'function_handle'),'Input "fcn" must be a function handle!')

% Allow multiple entries for data as an array of allowable types
if length(data)>1
    for ii = 1:length(data)
        data(ii) = editSimData(data(ii),address,target,fcn);
    end
    return
end

% Allow multiple entries for address as a cell array of string addresses
if iscell(address)
    for ii = 1:length(address)
        data = editSimData(data,address{ii},target,fcn);
    end
    return
end

if isa(data,'Simulink.SimulationData.Dataset') % Dataset elements names must be unique!
    assert(isequal(data.getElementNames(),unique(data.getElementNames(),'stable')),...
        'Element names of "data" must be unique to be compatible with editSimData!')
end
assert(ischar(address),'Input "address" must be a string or cell array of strings!')

% Split dot-based address into cell array so we can iterate over elements
address = regexp(address,'\.','split');
address = address(cellfun(@(str)~isempty(str),address));
% Step down into data to get addressed object
newdata = getData(data,address);
% Operate on all timeseries inside addressed object
newdata = walkData(newdata,target,fcn);
% Apply new data to master data
data = setData(data,address,newdata);

end

function data = getData(data,address)
% Steps down into "data" to get addressed object
for ii = 1:length(address)
    switch class(data)
        case 'Simulink.SimulationData.Dataset'
            assert(any(strcmp(address{ii},data.getElementNames())),...
                'Did not find element "%s" of "data.%s"',...
                address{ii},sprintf('%s.',address{1:ii-1}))
            data = data.get(address{ii});
        case 'Simulink.SimulationData.Signal'
            assert(any(strcmp(address{ii},fieldnames(data.Values))),...
                'Did not find element "%s" of "data.%s"',...
                address{ii},sprintf('%s.',address{1:ii-1}))
            data = data.Values.(address{ii});
        case 'struct'
            assert(any(strcmp(address{ii},fieldnames(data))),...
                'Did not find element "%s" of "data.%s"',...
                address{ii},sprintf('%s.',address{1:ii-1}))
            data = data.(address{ii});
        otherwise
            error('Don''t know what to do with an object of type "%s"!',class(data))
    end
end
end

function data = setData(data,address,newdata)
% A recursive function that sets the value of "data" at the location
% specified in "address" to the value of "newdata."
if ~isempty(address)
    switch class(data)
        case 'Simulink.SimulationData.Dataset'
            ii = find(strcmp(data.getElementNames(),address{1}));
            subdata = data.get(ii);
            subdata = setData(subdata,address(2:end),newdata);
            data = setElement(data,ii,subdata);
        case 'Simulink.SimulationData.Signal'
            data.Values.(address{1}) = setData(data.Values.(address{1}),address(2:end),newdata);
        case 'struct'
            data.(address{1}) = setData(data.(address{1}),address(2:end),newdata);
        otherwise
            error('Don''t know what to do with an object of type "%s"!',class(data))
    end
else
    data = newdata;
end
end

function data = walkData(data,target,fcn)
% A recursive function that scans objects of type
% * Simulink.SimulationData.Dataset,
% * Simulink.SimulationData.Signal, or
% * struct
% to find timeseries, on which it executes the (local) function "execute."
switch class(data)
    case 'Simulink.SimulationData.Dataset'
        for ii = 1:data.numElements
            data = data.setElement(ii,walkData(data.getElement(ii),target,fcn));
        end
    case 'Simulink.SimulationData.Signal'
        data.Values = walkData(data.Values,target,fcn);
    case 'struct'
        fields = fieldnames(data);
        for ii = 1:length(fields)
            data.(fields{ii}) = walkData(data.(fields{ii}),target,fcn);
        end
    case 'timeseries'
        data = execute(data,target,fcn);
    otherwise
        error('Don''t know what to do with an object of type "%s"!',class(data))
end
end

function ts = execute(ts,target,fcn)
% Executes input function on the timeseries, its Time, or its Data
if isempty(target) % operate on timeseries
    ts = fcn(ts);
else % Operate on Time/Data
    ts.(target) = fcn(ts.(target));
end
end