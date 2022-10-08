% Generate the Matlab logo and create a quilt

clear; 
close all; 

py.holoserverpy = py.importlib.reload(py.importlib.import_module('holoserverpy'));
py.holoserverpy.ws_init(); 

LKG_display = "portrait"; % can be '15.6' or '32', TODO: get this from driver!

switch LKG_display      % Params for the various displays
    case "portrait"
        Q_rows = 6;
        Q_cols = 8;
        Q_sizepx = 3840;  
        Q_aspect = Q_rows/Q_cols;
        Fov = 48;        

    case {"15.6", "16", "32", "8k"}
        Q_rows = 9;
        Q_cols = 5;
        Q_sizepx = 4096;  
        Q_aspect = 16/9;
        Fov = 53;        
end
if LKG_display == "8k" Q_sizepx = 8192; end


global quiltimage;
quiltimage = zeros(Q_sizepx,Q_sizepx,3,"uint8"); 

Q_size = Q_rows*Q_cols;
Q_imresX = floor(Q_sizepx / Q_cols); 
Q_imresY = floor(Q_sizepx / Q_rows); 

% File name format and python commands
fname = "MatlabLogo";
ext = "png";
quiltstr = strcat('_qs',num2str(Q_cols),'x',num2str(Q_rows),"a",num2str(Q_aspect,'%1.2f'));
rgbstr = "_rgb";
fn = strcat(fname, quiltstr, ".", ext); % image file name
fn_raw = strcat(fname, rgbstr, quiltstr, ".raw"); % raw file name for RGB24 data
pyscript = "/Users/javid/Documents/holoxica/projects/holoserverpy/holoserverpy.py";
cmd = strcat("python3 ", pyscript, " ", fn);

% draw the logo
L = 2000*membrane(1,100);
L = L - min(L(:));
s = surface(L);
s.EdgeColor = 'none';

f = gcf;
ax = gca;
f.MenuBar = "none";
f.ToolBar = "none";
%set(f,'HitTest','off')
% f.WindowButtonUpFcn = 'disp(''figure callback'')';
%f.WindowButtonUpFcn = @(src,evt)showAzEl(f,evt);
f.Position(3:4) = [Q_imresX/2 Q_imresY/2];

ax.ButtonDownFcn = 'disp(''axis callback'')';

%ax.ButtonDownFcn = @(f,ax)showAzEl(f,ax); 

h = rotate3d;
h.ActionPostCallback = @(src,evt)renderViews(f,evt);
az = -30;
el = 16;
view(az,el)

%view(3)

% ax.XLim = [-100 201];
% ax.YLim = [-100 201];
% ax.ZLim = [0 max(L(:))];

% ax.CameraPosition = [-145.5 -229.7 283.6];
% ax.CameraTarget = [77.4 60.2 63.9];

% ax.CameraPosition = [-245.5 -329.7 283.6];
% ax.CameraTarget = [0 0 0];
% ax.CameraUpVector = [0 0 1];
% ax.CameraViewAngle = 36.7;
%ax.CameraViewAngleMode = "manual";

%ax.Position = [0 0 1 1];
%ax.DataAspectRatio = [1 1 .9];

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

% Colours & map
s.FaceColor = [0.9 0.2 0.2];
f.Color = 'black'; % background colour

% Specular reflections
s.FaceLighting = 'gouraud';
s.AmbientStrength = 0.3;
s.DiffuseStrength = 0.6; 
s.BackFaceLighting = 'lit';
s.SpecularStrength = 1;
s.SpecularColorReflectance = 1;
s.SpecularExponent = 7;

axis off
%hold on;
%axis manual; 

M(Q_size) = struct('cdata',[],'colormap',[]);
az_offset = linspace(-Fov*0.5,Fov*0.5,Q_size);


% work out correct indexing of the quilt with bottom-left=1 and
% top-right=45
q = flipud(reshape(1:Q_size,Q_cols,Q_rows)')';
qq = q';    % sequence of tiles in the quilt, used for indexing
qidx = q(:)';
rpos=1:Q_imresY:Q_sizepx;  % indexing into larger quilt image
cpos=1:Q_imresX:Q_sizepx;

global shared;
shared.Q_cols = Q_cols;
shared.Q_rows = Q_rows;
shared.Q_aspect = Q_aspect;
shared.Q_size = Q_size;
shared.Q_imresX = Q_imresX;
shared.Q_imresY = Q_imresY;
shared.az_offset = az_offset;
shared.qq = qq;
shared.rpos = rpos;
shared.cpos = cpos;
shared.fn = fn;
shared.ext = ext; 
shared.cmd = cmd;
shared.diagnostic = false;


h.Enable = 'on';
renderViews("",""); % do a first render
while isvalid(f)
    pause(0.02);
end

imwrite(quiltimage,shared.fn,shared.ext); % write out the quilt for testing


%% Render multiple view points - callback when a mouse rotate is done
function renderViews(src,evt)
    global shared;
    global quiltimage;  
    
    ax = gca;
    f = gcf;
    h = rotate3d(f);
    setAllowAxesRotate(h,ax,false); % disable rotation during renders
    % f.Visible = "off";
    disp(ax.View);
    az = ax.View(1);
    el = ax.View(2);

    az_positions = az + shared.az_offset;
    tic
    for j = 1:shared.Q_size
        view(az_positions(j),el);
        [r, c] = find(shared.qq==j);
        row = shared.rpos(r);
        col = shared.cpos(c);
%         M(j) = getframe(f);
%         im = frame2im(M(j));
        im = frame2im(getframe(f));
        if shared.diagnostic
            im = insertText(im, [c*50 r*50], num2str(j),"FontSize",50); 
        end
        imsz = size(im);
        % quiltimage(row:row+shared.Q_imresY-1, col:col+shared.Q_imresX-1,:) ... % = im; 
        quiltimage(row:row+imsz(1)-1, col:col+imsz(2)-1, :) = im;
    end
    toc
    view(az,el);
    np_quilt = py.numpy.array(quiltimage); 
    py.holoserverpy.mat_quilt(np_quilt,shared.Q_cols,shared.Q_rows,shared.Q_aspect); 
    % f.Visible = "on";
    setAllowAxesRotate(h,ax,true); % enable rotating
    % imwrite(quiltimage,shared.fn,shared.ext);
    % status = system(shared.cmd)
end
