function [grad_trans] = mq_realign_sens(dir_name,elpfile,hspfile,...
    confile,mrkfile,bad_coil,method)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% mq_realign_sens: A function to realign the MEG sensors based on positions
% in mrk file (i.e. elp --> mrk). Designed for Yokogawa MEG-160 data.
% You can use rot3dfit or icp methods and enter up to 2 bad coils.
% 
%%%%%%%%%%%
% Inputs:
%%%%%%%%%%%
% - dir_name            = directory for saving
% - elpfile             = path to elp file
% - hspfile             = path to hsp file
% - confile             = path to con file
% - mrkfile             = path to mrk file
% - bad_coil            = list of bad coils (up to length of 2). Enter as:
%                         {'LPAred','RPAyel','PFblue','LPFwh','RPFblack'}
% - method              = method used to realign MEG sensors based on 5 
%                       marker coils. Use 'rot3dfit' or 'icp'. For some
%                       reason the usual rot3dfit method seems to fail 
%                       sometimes. Try using 'icp' in this case...
%
%%%%%%%%%%%
% Outputs:
%%%%%%%%%%%
% - grad_trans          = correctly transformed MEG sensors
% - shape               = headshape and fiducial information

% Author:  Robert Seymour (robert.seymour@mq.edu.au)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Check if bad_coils are entered correctly
if strcmp(bad_coil,'')
    disp('No bad coils marked');
else
    for check1 = 1:length(bad_coil)
        if ismember(bad_coil{check1},{'','LPAred','RPAyel','PFblue','LPFwh','RPFblack'}) == 0
            error('!!! Please enter bad_coils correctly in the form {LPAred,RPAyel,PFblue,LPFwh,RPFblack} !!!');
        end
    end
end

% Check if user has at least 3 'good' coils
assert(length(bad_coil)<3,'You need at least 3 good coils for accurate alignment\n');


% Check if MQ_MEG_Scripts has been added to your MATLAB path

if exist('parsePolhemus') == 2
    disp('MQ_MEG_Scripts is in your MATLAB path :)')
else
    error(['Did you add all of MQ_MEG_Scripts to your MATLAB path? ',...
        'Download from ',...
        'https://github.com/Macquarie-MEG-Research/MQ_MEG_Scripts',...
        ' ...and type addpath(genpath(path_to_MQ_MEG_Scripts))']);
end

%% Read the relevent subject data from file

% CD to right place
cd(dir_name); fprintf('\nCDd to the right place\n');

% Get Polhemus Points
disp('Reading elp and hspfile');
[shape]  = parsePolhemus(elpfile,hspfile);
shape   = ft_convert_units(shape,'mm');

% Read the grads from the con file
disp('Reading Sensors');
grad_con = ft_read_sens(confile); %in cm, load grads
grad_con = ft_convert_units(grad_con,'mm'); %in mm

% Read mrk_file
disp('Reading the mrk file');
mrk      = ft_read_headshape(mrkfile,'format','yokogawa_mrk');
mrk      = ft_convert_units(mrk,'mm'); %in mm

%% Perform Realighment Using Paul's Functions

if strcmp(bad_coil,'')
    disp('NO BAD MARKERS');
    markers                     = mrk.fid.pos([2 3 1 4 5],:);%reorder mrk to match order in shape
    
    % If the user specifed to use the icp sensor coregistratio approach use
    % this...
    if strcmp(method,'icp')
        fids_2_use = shape.fid.pnt(4:end,:);
        % For some reason this works better with only 3 points... check to
        % make sure this works for all?
        [R, T, err, dummy, info]    = icp(fids_2_use(1:5,:)',...
            markers(1:5,:)',100,'Minimize', 'point');
        meg2head_transm             = [[R T]; 0 0 0 1];%reorganise and make 4*4 transformation matrix
    % Otherwise use the original rot3dfit method
    else
        [R,T,Yf,Err]                = rot3dfit(markers,shape.fid.pnt(4:end,:));%calc rotation transform
        meg2head_transm             = [[R;T]'; 0 0 0 1];%reorganise and make 4*4 transformation matrix
    end
       
    disp('Performing re-alignment');
    grad_trans                  = ft_transform_geometry_PFS_hacked(meg2head_transm,grad_con); %Use my hacked version of the ft function - accuracy checking removed not sure if this is good or not
    grad_trans.fid              = shape; %add in the head information
    
    % Else if there is a bad marker
else
    fprintf(''); disp('TAKING OUT BAD MARKER(S)');

    badcoilpos = [];

    % Identify the bad coil
    for num_bad_coil = 1:length(bad_coil)
        pos_of_bad_coil = find(ismember(shape.fid.label,bad_coil{num_bad_coil}))-3;
        badcoilpos(num_bad_coil) = pos_of_bad_coil;
    end

    % Re-order mrk file to match elp file
    markers               = mrk.fid.pos([2 3 1 4 5],:);%reorder mrk to match order in shape
    % Now take out the bad marker(s) when you realign
    markers(badcoilpos,:) = [];

    % Get marker positions from elp file
    fids_2_use = shape.fid.pnt(4:end,:);
    % Now take out the bad marker(s) when you realign
    fids_2_use(badcoilpos,:) = [];

    % If there are two bad coils use the ICP method, if only one use
    % rot3dfit as usual
    disp('Performing re-alignment');

    if length(bad_coil) == 2
        [R, T, err, dummy, info]    = icp(fids_2_use', markers','Minimize', 'point');
        meg2head_transm             = [[R T]; 0 0 0 1];%reorganise and make 4*4 transformation matrix
        grad_trans                  = ft_transform_geometry_PFS_hacked(meg2head_transm,grad_con); %Use my hacked version of the ft function - accuracy checking removed not sure if this is good or not
        
        % Now take out the bad coil from the shape variable to prevent bad
        % plotting - needs FIXING for 2 markers (note: Dec 18)
        
        grad_trans.fid              = shape; %add in the head information
    else
        [R,T,Yf,Err]                = rot3dfit(markers,fids_2_use);%calc rotation transform
        meg2head_transm             = [[R;T]'; 0 0 0 1];%reorganise and make 4*4 transformation matrix
        grad_trans                  = ft_transform_geometry_PFS_hacked(meg2head_transm,grad_con); %Use my hacked version of the ft function - accuracy checking removed not sure if this is good or not
        
        % Now take out the bad coil from the shape variable to prevent bad
        % plotting
        shape.fid.pnt(badcoilpos+3,:) = [];
        shape.fid.label(badcoilpos+3,:) = [];
        grad_trans.fid              = shape; %add in the head information
    end
    
    
end

% Save the appropriate variables
disp('Saving data');
save shape shape
save grad_trans grad_trans


% Create figure to view relignment

ori = [180, -90, 0,90]
hfig = figure;

for v = 1:length(ori)
    subplot(2,2,v); ft_plot_sens(grad_trans,'edgealpha',0.7); 
    ft_plot_headshape(shape, 'vertexsize',5,'vertexcolor','r');
    hold on;  view([ori(v), 0]);
end

end