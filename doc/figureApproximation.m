close all;
clear all;

x1 = 0:0.001:1;
x1=x1*2*pi;

x2 = x1./(2*pi);

sine = sin(x1);

approx = 2*x2(1:250);
approx = [approx x2(1:500)+0.5];
approx = [approx ones(1, 250)];
approx = [approx flip(approx)];
approx = [approx -(approx)];


fig = figure;
plot(x2, sine, '--');
hold on;
plot(x2, [approx(1:4:end) 0]);
ylim([-1.1 1.1]);
grid on;
xticks(0:0.25:1);
yticks(-1:0.5:1);
xlabel('Range of phase accumulator (×2^{N_{bitA}})');
ylabel('Output (×2^{N_{bitDAC}})');
legend('Ideal sine wave', 'Our approximation');
ax = gca;
ax.XMinorGrid = 'on';
ax.XAxis.MinorTickValues = 0:0.25/4:1;

set(gcf, 'PaperUnits', 'centimeters');
set(fig,'PaperSize',[15 10]); %set the paper size to what you want  
print(fig,'figureApproximation','-dpdf', '-fillpage') % then print it