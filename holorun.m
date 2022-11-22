% Running and testing the holoquilt

% create a 3D plot fig and show it on the display

clear all; close all;

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
