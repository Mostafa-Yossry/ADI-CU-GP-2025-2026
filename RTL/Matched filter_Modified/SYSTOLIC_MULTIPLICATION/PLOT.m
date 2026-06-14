function PLOT(TYPE,number_of_tests, SQNR)

  switch TYPE
      case "SQNR_G"
            figure;
            x = 1:1:number_of_tests;
            y = SQNR;
            semilogy(x, y, "linewidth", 2);
            grid on;
            xlabel("Test Number");
            ylabel("SQNR");
            title("SQNR for Matrix Multiplication size 8x8 = 8x8 * 8x8");
            fprintf("Mean SQNR for G         = %0.3f\n",sum(SQNR)/number_of_tests);

      case "SQNR_Z"
            figure;
            x = 1:1:number_of_tests;
            y = SQNR;
            semilogy(x, y, "linewidth", 2);
            grid on;
            xlabel("Test Number");
            ylabel("SQNR");
            title("SQNR for Matrix Multiplication size 8x1 = 8x8 * 8x1");
            fprintf("Mean SQNR for Z         = %0.3f\n",sum(SQNR)/number_of_tests);

      case "SQNR_GZ"
            figure;
            x = 1:1:number_of_tests;
            y = SQNR;
            semilogy(x, y, "linewidth", 2);
            grid on;
            xlabel("Test Number");
            ylabel("SQNR");
            title("SQNR for Matrix Multiplication size 8x1 = 8x8 * 8x1");
            fprintf("Mean SQNR for G^-1 * Z  = %0.3f\n",sum(SQNR)/number_of_tests);

      case "SQNR_All"
            figure;
            x = 1:1:number_of_tests;
            y = SQNR;
            semilogy(x, y, "linewidth", 2);
            grid on;
            xlabel("Test Number");
            ylabel("SQNR");
            title("SQNR for All Equalizer");
            SQNR_Equalizer = sum(SQNR)/number_of_tests;
            SQNR_FFT       = 48.35;
            SQNR_System    = -10 * log10( 10.^(-SQNR_FFT/10) + 10.^(-SQNR_Equalizer/10) );
            fprintf("Mean SQNR for Equalizer = %0.3f\n",SQNR_Equalizer);
            fprintf("Mean SQNR for FFT and Equalizer = %0.3f\n",SQNR_System);
  end
end