% 1. تعريف البيانات (Data Definition)
iterations = 0:64; % محور x من 1 لـ 10
test_accuracy = [1,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8];

% 2. رسم البيانات (Plotting)
figure; % فتح نافذة رسم جديدة
plot(iterations, test_accuracy, '-o', 'LineWidth', 2, 'MarkerSize', 8);

% 3. تسمية المحاور والعنوان (Labeling)
xlabel('Stage');
ylabel('Integer Width');
title('Fixed point for G');

% 4. تحسين شكل الرسم (Formatting)
grid on; % إضافة شبكة للرسم لتسهيل القراءة
axis([0 64 0 8]); % ضبط حدود المحاور (اختياري)