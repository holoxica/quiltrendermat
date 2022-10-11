% Show 3D image plots on the Looking Glass 3D Light Field displays, where a
% quilt corresponding to renders from multiple viewpoints is rendered.
% The quilt is send to a python utility to display quilt using the 
% HoloPlay driver. 
%
% (c) Holoxica Limited, 2022. All rights reserved. 

clear; 
close all; 

%% initialise display, driver and python utility
global Quilt;
pe = pyenv;
if pe.Status == 'NotLoaded'
    pyenv("ExecutionMode","OutOfProcess","Version","3.9");    
    py.list; % Call a Python function to load interpreter
    py.holoserverpy = py.importlib.reload(py.importlib.import_module('holoserverpy'));
end

initialise3Ddisplay(); 

Quilt.image = zeros(Quilt.sizepx,Quilt.sizepx,3,"uint8"); 
Quilt.size = Quilt.rows*Quilt.cols;
Quilt.imresX = floor(Quilt.sizepx / Quilt.cols); 
Quilt.imresY = floor(Quilt.sizepx / Quilt.rows); 

% File name format and python commands
fname = "Matlablogo";
ext = "png";
quiltstr = strcat('_qs',num2str(Quilt.cols),'x',num2str(Quilt.rows), ...
                  "a",num2str(Quilt.aspect,'%1.2f'));
fn = strcat(fname, quiltstr, ".", ext); % image file name
pyscript = "holoserverpy.py";
cmd = strcat("python3 ", pyscript, " ", fn);

[f, ax] = surfshow(fname);

ax.Interactions = zoomInteraction;
tb = axtoolbar(ax,"default");
tb.SelectionChangedFcn = @(src,evt)toolbarSelection(src,evt);
%f.MenuBar = "none";
%f.ToolBar = "auto";

%f.WindowButtonUpFcn = "disp('figure callback')";
f.WindowScrollWheelFcn = "disp('Scroll callback')";
f.Position(3:4) = [Quilt.imresX Quilt.imresY]*0.71; % set resolution of viewport

h = rotate3d;
h.ActionPostCallback = @(src,evt)renderViews(f,evt);    % Main callback

%M(Quilt.size) = struct('cdata',[],'colormap',[]);

% work out correct indexing of the quilt with bottom-left=1 and
% top-right=total nr. views
q = flipud(reshape(1:Quilt.size,Quilt.cols,Quilt.rows)')';
qq = q';    % sequence of tiles in the quilt, used for indexing
qidx = q(:)';
rpos=1:Quilt.imresY:Quilt.sizepx;  % indexing into larger quilt image
cpos=1:Quilt.imresX:Quilt.sizepx;

global shared;
shared.qq = qq;
shared.rpos = rpos;
shared.cpos = cpos;
shared.fn = fn;
shared.ext = ext; 
shared.cmd = cmd;
shared.diagnostic = false;

fig2 = figure;
fig2.MenuBar = "none";
%fig2.ToolBar = "none";
fig2.Color = f.Color;
fig2.Colormap = f.Colormap;
fig2.Position(1:2) = f.Position(1:2) + [0 -Quilt.imresY];    
fig2.Position(3:4) = [Quilt.imresX/2 Quilt.imresY/2]; % set resolution of renderer
%rotate3d;
%axis off;
axis manual;
hold off;
shared.fig2 = fig2;

figure(f);

h.Enable = 'on';
renderViews("",""); % do a first render
done = false;
while not(done)
    done = not(isvalid(f)); 
    pause(0.02);
end
imwrite(Quilt.image,shared.fn,shared.ext); % write out the quilt for testing
fprintf('Quilt written to: %s \n',fn);
close(fig2);

%% Render multiple view points - callback when a mouse rotate is done
function renderViews(src,evt)
    global Quilt; 
    global shared;
    
    f = gcf;
    ax = gca(f);
    h = rotate3d(f);
    %campos = ax.CameraPosition; 
    setAllowAxesRotate(h,ax,false); % disable rotation during renders
    clf(shared.fig2); 
    copyobj(ax,shared.fig2);
    figure(shared.fig2);

    dAz = Quilt.viewCone/Quilt.size; 
    camorbit(-Quilt.viewCone*0.5-dAz, 0, 'camera'); % start at the leftmost view 
    tic
    for j = 1:Quilt.size
        %figure(shared.fig2);
        shared.fig2.Visible = "on";
        camorbit(dAz, 0, 'camera'); % advance cam by one position
        %shared.fig2.Visible = "off";
        im = frame2im(getframe(shared.fig2));
        [r, c] = find(shared.qq==j);
        row = shared.rpos(r);
        col = shared.cpos(c);
        if shared.diagnostic
            im = insertText(im, [50*floor(j/20+1) 40*mod(j,15)], num2str(j),"FontSize",30, "TextColor","yellow"); 
        end
        imsz = size(im);
        Quilt.image(row:row+imsz(1)-1, col:col+imsz(2)-1, :) = im;
    end
    toc
    shared.fig2.Visible = "off";
    if Quilt.displayPresent
        np_quilt = py.numpy.array(Quilt.image); 
        py.holoserverpy.mat_quilt(np_quilt,Quilt.cols,Quilt.rows,Quilt.aspect); 
    end
    setAllowAxesRotate(h,ax,true); % enable rotating
    % imwrite(Quilt.image,shared.fn,shared.ext);     % write to disk
    % status = system(shared.cmd)                   % call python via cmd line
end


function toolbarSelection(src,evt,~)
    disp(src);
    disp(evt);

end


%% Initialise the 3D display using the python utility
function initialise3Ddisplay()
    clear py
    global Quilt;
    Quilt.displayPresent = false;
    status = {false}; 
    LKG_display = "portrait"; % can be '15.6' or '32', used for default if no display connected, otherwise get info from driver

    %    pe = pyenv;
%     % Check the python utility is present and working
%     if not(isfile("holoserverpy.py"))
%         warning("Python holoserver utility not found, please contact Holoxica for this.")
%     elseif pe.Status == 'NotLoaded'
%         pyenv("ExecutionMode","OutOfProcess","Version","3.9");       
%         py.list; % Call a Python function to load interpreter
%     else
%         py.list
%     end
%    py.holoserverpy = py.importlib.reload(py.importlib.import_module('holoserverpy'));

    try
        status = py.holoserverpy.ws_init(); % initialise contact with utility
    catch
        warning("Holoplay driver is not installed or running, please fix")
    end

    if status{1}==false
        fprintf('No 3D display found, using default params for %s \n', LKG_display);
    else
        driver = struct(status{2});
        fprintf("HoloPlay driver version: %s \n",string(driver.version)); 
        vals  = cell(driver.devices);
        if isempty(vals)
            fprintf("Please switch on the display or reset the HoloPlay driver \n");
        else
            params = struct(vals{1});
            defaultQuilt  = struct(params.defaultQuilt);
            Quilt.cols = double(defaultQuilt.tileX);
            Quilt.rows = double(defaultQuilt.tileY);
            Quilt.sizepx = double(defaultQuilt.quiltX);
            Quilt.aspect = double(defaultQuilt.quiltAspect);
            calibration = struct(params.calibration);
            viewCone = struct(calibration.viewCone);
            Quilt.viewCone = double(viewCone.value);
            LKG_display = ""; 
            Quilt.displayPresent = true;
        end 
    end
    
    % Default parameters if no display is present
    
    switch LKG_display      % Params for the various displays
        case "portrait"
            Quilt.rows = 6;
            Quilt.cols = 8;
            Quilt.sizepx = 3840;  
            Quilt.aspect = Quilt.rows/Quilt.cols;
            Quilt.viewCone = 40;        
    
        case {"15.6", "16", "32", "8k"}
            Quilt.rows = 9;
            Quilt.cols = 5;
            Quilt.sizepx = 4096;  
            Quilt.aspect = 16/9;
            Quilt.viewCone = 53;        
    end
    if LKG_display == "8k" Quilt.sizepx = 8192; end


end


%% Define different kinds of images to show

function [f, ax] = surfshow(fname)

    switch fname

        case "Matlablogo"
            L = 1000*membrane(1,100);
            %L = L - min(L(:));
            s = surface(L,'EdgeColor','none');
            view(3);
            % Colours & map
            s.FaceColor = [0.9 0.2 0.2];
            
            % Specular reflections
            s.FaceLighting = 'gouraud';
            s.AmbientStrength = 0.3;
            s.DiffuseStrength = 0.6; 
            s.BackFaceLighting = 'lit';
            s.SpecularStrength = 1;
            s.SpecularColorReflectance = 1;
            s.SpecularExponent = 7;

            % Lighting 
            l1 = light;
            l1.Position = [60 300 80];
            l1.Style = 'local';
            l1.Color = [0 0.8 0.8];
             
            l2 = light;
            l2.Position = [.5 -1 .4];
            l2.Color = [0.8 0.8 0];
            
            l3 = light;
            l3.Position = [60 -300 80];
            l3.Style = 'local';
            l3.Color = [0 0.8 0.8];

            axis off;
            f = gcf;
            f.Color = "black";

        case "Peaks"
            s = surf(peaks);
            colormap("hsv");

        case "Worldmap"   
            [x,y,z] = sphere(50);          % create a sphere 
            s = surface(x,y,z);            % plot spherical surface
            load topo topo; 
            s.FaceColor = 'texturemap';    % use texture mapping
            s.CData = topo;                % set color data to topographic data
            s.EdgeColor = 'none';          % remove edges
            s.FaceLighting = 'gouraud';    % preferred lighting for curved surfaces
            s.SpecularStrength = 0.4;      % change the strength of the reflected light
            
            light('Position',[-1 0 1])     % add a light
            axis square off                % set axis to square and remove axis

    end

    axis manual;    % don't autoscale axes, freeze to current values

    f = gcf;
    ax = gca;

    % Cammera parameters
    ax.Projection = "perspective";
    ax.CameraPositionMode = "manual";
    ax.CameraTargetMode = "manual";
    ax.CameraViewAngleMode = "manual";

    

end