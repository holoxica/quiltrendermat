% Running and testing the holoquilt

% create a 3D plot fig and show it on the display

clear all; close all;


load desiredSynthesizedAntenna;

clf;
pattern(mysteryAntenna,3e8,'CoordinateSystem','polar','Type','powerdb');
view(50,20);
ax = gca;
ax.Position = [-0.15 0.1 0.9 0.8];
camva(4.5);
campos([520 -250 200]);

h1 = holoquilt(gcf);
pause

t = 0:pi/500:40*pi;
xt = (3 + cos(sqrt(32)*t)).*cos(t);
yt = sin(sqrt(32) * t);
zt = (3 + cos(sqrt(32)*t)).*sin(t);
plot3(xt,yt,zt)
axis equal
xlabel('x(t)')
ylabel('y(t)')
zlabel('z(t)')

h1 = holoquilt(gcf);

pause;
figure
t = 0:pi/20:10*pi;
xt = sin(t);
yt = cos(t);
plot3(xt,yt,t,'-o','Color','b','MarkerSize',10,...
    'MarkerFaceColor','#D9FFFF')
h2 = holoquilt(gcf);
