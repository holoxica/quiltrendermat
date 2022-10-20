% Show 3D image plots on the Looking Glass 3D Light Field displays, where a
% quilt corresponding to renders from multiple viewpoints is generated.
% The quilt is send to a python utility to display quilt using the 
% HoloPlay driver. 
%
% (c) Holoxica Limited, 2022. All rights reserved. www.holoxica.com

clear; 
close all; 

%% initialise display, driver and python utility
pyscript = "holoserverpy.py";
defaultDisplay = "portrait"; 

% Check the python interpreter and utility are present and working. 
% Note that the utility will require external libraries to be installed
% from Matlab via:
% >> system("pip3 install websocket-client cbor2 opencv-python")
utilityPresent = isfile(pyscript);
pe = pyenv;
if not(utilityPresent)
    warning("Python holoserver utility not found, please contact Holoxica for this.")
elseif strcmp(pe.Status, 'NotLoaded')
    pyenv("ExecutionMode","OutOfProcess","Version","3.9");    
    py.list; % Call a Python function to load interpreter
    py.holoserverpy = py.importlib.reload(py.importlib.import_module('holoserverpy'));
end

global Quilt;
Quilt = initialise3Ddisplay(utilityPresent,defaultDisplay); 
[f, surfnames, fname] = surfshow(); % generate a 3D surface
Quilt.renderFig = renderFigGen(f, [Quilt.imresX Quilt.imresY]);
Quilt.diagnostic = false;

% File name format and python command line
ext = "png";
quiltstr = strcat('_qs',num2str(Quilt.cols),'x',num2str(Quilt.rows), ...
                  "a",num2str(Quilt.aspect,'%1.2f'));
fn = strcat("Quilt", quiltstr, ".", ext); % image file name
cmd = strcat("python3 ", pyscript, " ", fn);

global shared;
shared.fn = fn;
shared.ext = ext; 
shared.cmd = cmd;
shared.keyPressed = ""; 


%% Main game loop
figure(f);
ax = gca;
h = rotate3d(f); % handlt to rotation mode on axes
h.Enable = 'on';
animation = false;
renderViews("",""); % do a first render
done = false;
while not(done)
    done = not(isvalid(h)); 
    if isvalid(h) h.Enable = 'off'; end
    pause(0.1);
    if shared.keyPressed ~= ""
        
        switch shared.keyPressed
            case 'a'    % animation
                animation = not(animation);

            case 'd'
                clf(f); 
                shared.diagnostic = not(shared.diagnostic);

            case 'rightarrow'   % move to next surface !! need to update fname
                animation = false;
                clf(f);
                idx = find(contains(surfnames,fname));  % current index
                idx = mod(idx,length(surfnames))+1;     % next image
                fname = surfnames(idx);
                [f, ax] = surfshow(fname);
        end
        fprintf("Key: %s \n",shared.keyPressed);
        shared.keyPressed = ""; 
        renderViews("",""); % force a render
    end
    if isvalid(h) h.enable = 'on'; end
    pause(0.2)
    if animation
        figure(f);
        ax.View = ax.View + [2 0]; 
    end
end

% write the final quilt out
fn = strcat(fname, quiltstr, ".", ext); % image file name
imwrite(Quilt.image,shared.fn,shared.ext); % write out the quilt for testing
fprintf('Quilt written to: %s \n',fn);
close(Quilt.renderFig);


%% Render multiple view points - callback when a mouse rotate is done
function renderViews(src,evt)
% Multiview rendering to make a quilt, starting with the leftmost view and
% orbit the camera across the scene, taking snapshots of the renderfig as
% we go. The snapshots are added to the quilt image matrix
    global Quilt; 
    % global shared;
    
    if Quilt.busyrendering == true % ensure only one render job at a time 
        return
    end
    Quilt.busyrendering = true;
    f = gcf;
    ax = gca(f);
    h = rotate3d(f);
    setAllowAxesRotate(h,ax,false); % disable rotation during renders
    clf(Quilt.renderFig); 
    Quilt.renderFig.Color = f.Color;
    Quilt.renderFig.Colormap = f.Colormap;
    copyobj(ax,Quilt.renderFig);
    figure(Quilt.renderFig);

    dAz = Quilt.viewCone/Quilt.size; 
    camorbit(-Quilt.viewCone*0.5-dAz, 0, 'camera'); % start at the leftmost view 
    tic
    for j = 1:Quilt.size
        %figure(shared.renderFig);
        Quilt.renderFig.Visible = "on";
        camorbit(dAz, 0, 'camera'); % advance cam by one position
        %shared.renderFig.Visible = "off";
        im = frame2im(getframe(Quilt.renderFig));
        [r, c] = find(Quilt.qq==j);
        row = Quilt.rpos(r);
        col = Quilt.cpos(c);
        if Quilt.diagnostic
            im = insertText(im, [50*floor(j/20+1) 40*mod(j,15)], ... 
                        num2str(j), "FontSize",30, "TextColor","yellow"); 
        end
        imsz = size(im);
        Quilt.image(row:row+imsz(1)-1, col:col+imsz(2)-1, :) = im;
    end
    toc
    Quilt.renderFig.Visible = "off";
    if Quilt.displayPresent
        np_quilt = py.numpy.array(Quilt.image); 
        py.holoserverpy.mat_quilt(np_quilt,Quilt.cols,Quilt.rows,Quilt.aspect); 
    end
    Quilt.busyrendering = false; 
    %h.Enable = 'on';
    setAllowAxesRotate(h,ax,true); % enable rotating
    % imwrite(Quilt.image,shared.fn,shared.ext);     % write to disk
    % status = system(shared.cmd)                   % call python via cmd line
end


%% Callbacks

function keypressedCallback(src,evt,~)
    %disp(src);
    %disp(evt);
    global shared;    
    shared.keyPressed = evt.Key; % register this for the mainloop to pick up
end


function scrollCallback(src,evt)
    global shared;
    shared.keyPressed = "rightarrow"; % move on to next surface
end


%%
function Quilt = initialise3Ddisplay(utilityPresent,defaultDisplay)
% Initialise the 3D display via the python utility that returns info
% from the HoloPlay driver. The info contains all of the parameters related
% to the quilt and the display itself. If this display is not connected
% then a default set of parameters is used.

    Quilt.displayPresent = false;
    status = {false}; 
    LKG_display = defaultDisplay; % can be '15.6' or '32', used for default if no display connected, otherwise get info from driver

    if utilityPresent
        try
            status = py.holoserverpy.ws_init(); % initialise contact with utility
        catch
            warning("Holoplay driver is not installed or running, please fix")
        end
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
            LKG_display = string(params.hardwareVersion); 
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
    Quilt.LKG_display = LKG_display;

    % derived parameters, useful later on
    Quilt.size = Quilt.rows*Quilt.cols;
    Quilt.imresX = floor(Quilt.sizepx / Quilt.cols); 
    Quilt.imresY = floor(Quilt.sizepx / Quilt.rows); 

    % work out correct indexing of the quilt with bottom-left=1 and
    % top-right=total nr. views
    q = flipud(reshape(1:Quilt.size,Quilt.cols,Quilt.rows)')';
    qq = q';    % sequence of tiles in the quilt, used for indexing
    qidx = q(:)';
    rpos=1:Quilt.imresY:Quilt.sizepx;  % indexing into larger quilt image
    cpos=1:Quilt.imresX:Quilt.sizepx;
    Quilt.qq = qq;
    Quilt.rpos = rpos;
    Quilt.cpos = cpos;

    % Build the quilt image
    Quilt.image = zeros(Quilt.sizepx,Quilt.sizepx,3,"uint8");

    Quilt.busyrendering = false;

    Quilt.diagnostic = false; % diagnostic to save a quilt as we go

end


%% Define different kinds of 3D images to show
function [f, surfnames, name] = surfshow(varargin)
    
    surfnames = ["Matlablogo", "Peaks", "Worldmap"];
    if nargin == 0
        name = surfnames(1);
    elseif nargin == 1 
        if sum(contains(surfnames,varargin{1})) == 0
            name = surfnames(1);
        else
            name = varargin{1};
        end
    else 
        name = surfnames(1);
    end

    f = gcf;

    switch name

        case "Matlablogo"
            L = 1000*membrane(1,100);
            %L = L - min(L(:));
            s = surface(L,'EdgeColor','none');
            view(3);
            % Colours & map
            s.FaceColor = [0.9 0.2 0.2];
            colormap("default");
            
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
            f.Color = "black";

        case "Peaks"
            s = surf(peaks);
            colormap("hsv");
            f.Color = "white";

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
            f.Color = "white";
            colormap('default'); 

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


%% Take a figure and show it in 3D
function [renderFig] = renderFigGen(f, imres)
% Prepare the main figure for 3D visualisation and create an auxillary
% figure for the actual multi-view rendering

    imresX = imres(1);
    imresY = imres(2);

    % Set up the main figure for 3D manipulation and visualisation
    figure(f);
    ax = gca;

    % Cammera parameters
    ax.Projection = "perspective";
    ax.CameraPositionMode = "manual";
    ax.CameraTargetMode = "manual";
    ax.CameraViewAngleMode = "manual";

    ax.Interactions = zoomInteraction;
    tb = axtoolbar(ax,"default");
    tb.SelectionChangedFcn = @(src,evt)testCallback(src,evt);
    f.MenuBar = "none";
    %f.ToolBar = "auto";
    
    %f.WindowButtonUpFcn = "disp('figure callback')";
    f.WindowScrollWheelFcn = @(src,evt)scrollCallback(src,evt); %"disp('Scroll callback')";
    f.WindowKeyPressFcn = @(src,evt)keypressedCallback(src,evt); %"disp('Key realease callback')";
    %f.Position(3:4) = [Quilt.imresX Quilt.imresY]*0.71; % set resolution of viewport
    
    h = rotate3d;
    h.ActionPostCallback = @(src,evt)renderViews(f,evt); % Callback for renderer

    % A second figure is used for the actual rendering. It is normally invisible
    renderFig = figure;
    renderFig.MenuBar = "none";
    %renderFig.ToolBar = "none";
    renderFig.Color = f.Color;
    renderFig.Colormap = f.Colormap;
    renderFig.Position(1:2) = f.Position(1:2) + [0 -imresY];    
    renderFig.Position(3:4) = [imresX/2 imresY/2]; % set resolution of renderer
    axis manual;
    hold off;

    figure(f); % back to the main fig

end