% Show 3D image plots on the Looking Glass 3D Light Field displays, where a
% quilt corresponding to renders from multiple viewpoints is generated.
% The quilt is send to a python utility to display quilt using the 
% HoloPlay driver. 
%
% (c) Holoxica Limited, 2022. All rights reserved. www.holoxica.com


classdef holoquilt

    properties
        displayPresent = false;
        utilityPresent; % = isfile("holoserverpy.py");
        %status = { false };
        LKG_display;
        quilt;
        defaultDisplay = "portrait";
        busyrendering = false;  % can't interrupt a quilt being built
        diagnostic = false;     % show individual views
        figname; 

    end

    %%
    properties (Access=private)
        pe = pyenv;        
        pyscript = "holoserverpy.py";
        fig
        ax
        renderFig
    end

    properties (Dependent)

    end

    %%
    methods
        
        % constructor
        function obj = holoquilt(varargin)
            if isempty(obj.quilt)
                obj = init3Ddisplay(obj);
            end
            if nargin == 0  % no figure handle given
                [obj.fig, obj.ax, obj.figname] = holoquilt.surfshow(); % generate a 3D fig
            end
            if isempty(obj.renderFig)
               obj.renderFig = renderFigInit(obj);
            end
            obj = renderViews(obj);
        end % constructor


        function obj = renderViews(obj)
        % Multiview rendering to make a quilt, starting with the leftmost view and
        % orbit the camera across the scene, taking snapshots of the renderfig as
        % we go. The snapshots are added to the quilt image matrix
        % - callback when a mouse rotate is done

            if obj.busyrendering == true % ensure only one render job at a time 
                return
            end

            obj.busyrendering = true;
            figure(obj.fig)
            axs = gca;
            h = rotate3d(obj.fig);
            setAllowAxesRotate(h,axs,false); % disable rotation during renders
            clf(obj.renderFig); 
            obj.renderFig.Color = obj.fig.Color;
            obj.renderFig.Colormap = obj.fig.Colormap;
            copyobj(axs,obj.renderFig);
            figure(obj.renderFig);
            Quilt = obj.quilt;
            dAz = Quilt.viewCone/Quilt.size; 
            camorbit(-Quilt.viewCone*0.5-dAz, 0, 'camera'); % start at the leftmost view 
            tic
            for j = 1:Quilt.size
                %figure(shared.renderFig);
                Quilt.renderFig.Visible = "on";
                camorbit(dAz, 0, 'camera'); % advance cam by one position
                %shared.renderFig.Visible = "off";
                im = frame2im(getframe(obj.renderFig));
                [r, c] = find(Quilt.qq==j);
                row = Quilt.rpos(r);
                col = Quilt.cpos(c);
                if obj.diagnostic
                    im = insertText(im, [50*floor(j/20+1) 40*mod(j,15)], ... 
                                num2str(j), "FontSize",30, "TextColor","yellow"); 
                end
                imsz = size(im);
                Quilt.image(row:row+imsz(1)-1, col:col+imsz(2)-1, :) = im;
            end
            toc
            obj.renderFig.Visible = "off";
            if obj.displayPresent
                np_quilt = py.numpy.array(Quilt.image); 
                py.holoserverpy.mat_quilt(np_quilt,Quilt.cols,Quilt.rows,Quilt.aspect); 
            end
            obj.busyrendering = false; 
            %h.Enable = 'on';
            setAllowAxesRotate(h,axs,true); % enable rotation
            % imwrite(Quilt.image,shared.fn,shared.ext);     % write to disk
            % status = system(shared.cmd)                   % call python via cmd line

        end % renderViews



        function renderfig = renderFigInit(obj)
        % Prepare the main figure for 3D visualisation and create an auxillary
        % figure for the actual multi-view rendering
              
            % Set up the main figure for 3D manipulation and visualisation
            figure(obj.fig);
       
            % Cammera parameters
            obj.ax.Projection = "perspective";
            obj.ax.CameraPositionMode = "manual";
            obj.ax.CameraTargetMode = "manual";
            obj.ax.CameraViewAngleMode = "manual";
        
            obj.ax.Interactions = zoomInteraction;
            tb = axtoolbar(obj.ax,"default");
            %tb.SelectionChangedFcn = @(src,evt)testCallback(src,evt);
            obj.fig.MenuBar = "none";
            %f.ToolBar = "auto";
            
            %%f.WindowButtonUpFcn = "disp('figure callback')";
            %f.WindowScrollWheelFcn = @(src,evt)scrollCallback(src,evt); %"disp('Scroll callback')";
            %f.WindowKeyPressFcn = @(src,evt)keypressedCallback(src,evt); %"disp('Key realease callback')";
            obj.fig.Position(3:4) = [obj.quilt.imresX obj.quilt.imresY]*0.71; % set resolution of viewport
            
            h = rotate3d;
            %h.ActionPostCallback = @(src,evt)renderViews(f,evt); % Callback for renderer
        
            % A second figure is used for the actual rendering. It is normally invisible
            renderfig = figure;
            renderfig.MenuBar = "none";
            %renderFig.ToolBar = "none";
            renderfig.Color = obj.fig.Color;
            renderfig.Colormap = obj.fig.Colormap;
            renderfig.Position(1:2) = obj.fig.Position(1:2) + [0 -obj.quilt.imresY];    
            renderfig.Position(3:4) = [obj.quilt.imresX obj.quilt.imresY]*0.5; % set resolution of renderer
            axis manual;
            hold off;
            
            figure(obj.fig); % back to the main fig
        
        end % renderFigGen


        function obj = init3Ddisplay(obj)
        % Initialise the 3D display via the python utility that returns info
        % from the HoloPlay driver. The info contains all of the parameters related
        % to the quilt and the display itself. If this display is not connected
        % then a default set of parameters is used.


            obj.utilityPresent = isfile(obj.pyscript);
            if not(obj.utilityPresent)
                warning("Python holoserver utility not found, please contact Holoxica for this.")
            elseif strcmp(obj.pe.Status, 'NotLoaded')
                pyenv("ExecutionMode","OutOfProcess","Version","3.9");    
                obj.py.list; % Call a Python function to load interpreter
                obj.py.holoserverpy = py.importlib.reload(py.importlib.import_module('holoserverpy'));
                disp("Python interpreter loaded")
            end

            % Interrogate the HoloPlay driver
            if obj.utilityPresent
                try
                    status = py.holoserverpy.ws_init(); % initialise contact with utility
                catch
                    warning("Holoplay driver is not installed or running, please fix")
                end
            end
            obj.LKG_display = obj.defaultDisplay;
            Quilt = struct;
            % Interpret return from driver
            if status{1}==false
                fprintf('No 3D display found, using default params for %s \n', obj.LKG_display);
            else
                driver = struct(status{2});
                fprintf("HoloPlay driver version: %s \n",string(driver.version)); 
                vals  = cell(driver.devices);
                if isempty(vals)
                    fprintf("Please switch the display ON or reset the HoloPlay driver \n");
                else
                    % Found a display! Extract parameters
                    params = struct(vals{1});
                    defaultQuilt  = struct(params.defaultQuilt);
                    Quilt.cols = double(defaultQuilt.tileX);
                    Quilt.rows = double(defaultQuilt.tileY);
                    Quilt.sizepx = double(defaultQuilt.quiltX);
                    Quilt.aspect = double(defaultQuilt.quiltAspect);
                    calibration = struct(params.calibration);
                    viewCone = struct(calibration.viewCone);
                    Quilt.viewCone = double(viewCone.value);
                    obj.LKG_display = string(params.hardwareVersion); 
                    obj.displayPresent = true;
                end 
            end 
            
            % Default parameters if no display is present
            if not (obj.displayPresent)
                switch obj.LKG_display      % Params for the various displays
                    case "portrait"
                        Quilt.rows = 6;
                        Quilt.cols = 8;
                        Quilt.sizepx = 3840;  
                        Quilt.aspect = Quilt.rows / Quilt.cols;
                        Quilt.viewCone = 40;        
                
                    case {"15.6", "16", "32", "8k"}
                        Quilt.rows = 9;
                        Quilt.cols = 5;
                        Quilt.sizepx = 4096;  
                        Quilt.aspect = 16/9;
                        Quilt.viewCone = 53;        
                end
                if obj.LKG_display == "8k" 
                    Quilt.sizepx = 8192; 
                end
            end

            % derived parameters, useful later on
            Quilt.size = Quilt.rows * Quilt.cols;
            Quilt.imresX = floor(Quilt.sizepx / Quilt.cols);
            Quilt.imresY = floor(Quilt.sizepx / Quilt.rows);

            % work out correct indexing of the quilt with bottom-left=1 and
            % top-right=total nr. views
            q = flipud(reshape(1:Quilt.size,Quilt.cols,Quilt.rows)')';
            Quilt.qq = q';    % sequence of tiles in the quilt, used for indexing
            Quilt.rpos=1:Quilt.imresY:Quilt.sizepx;  % indexing into larger quilt image
            Quilt.cpos=1:Quilt.imresX:Quilt.sizepx;

            % Initialise the quilt image
            Quilt.image = zeros(Quilt.sizepx,Quilt.sizepx,3,"uint8");

            obj.quilt = Quilt; 
                    
        end % init3Ddisplay



    end % public methods

    %%
    methods (Static)
        function [fig, ax, figname] = surfshow(varargin)
        % Define different kinds of 3D images to show
            
            surfnames = ["Matlablogo", "Peaks", "Worldmap"];
            r = randi(length(surfnames)); 
            if nargin == 0
                figname = surfnames(r);
            elseif nargin == 1 
                if sum(contains(surfnames,varargin{1})) == 0
                    figname = surfnames(1);
                else
                    figname = varargin{r};
                end
            else 
                figname = surfnames(r);
            end

            figure;
            fig = gcf;
        
            switch figname
        
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
                    fig.Color = "black";
        
                case "Peaks"
                    s = surf(peaks);
                    colormap("hsv");
                    fig.Color = "white";
        
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
                    fig.Color = "white";
                    colormap('default'); 
        
            end
            
            fig.Name = figname;
            axis manual;    % don't autoscale axes, freeze to current values
            ax = gca;
              
        end % surfshow


    end % static methods


end % classdef