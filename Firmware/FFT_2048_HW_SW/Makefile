APP = main.c

# The path to your DSP library headers
DSP_LIB = $(HOME)/pulp-dsp

# Compiling the new single-core versions directly
APP_SRCS = main.c  
#butterfly_driver.c

# Compilation flags (O3 for maximum optimization, PMSIS definition, and DSP includes)
APP_CFLAGS += -O3 -g -D__PMSIS__=1 -I$(DSP_LIB)/include
APP_CFLAGS += -O3 -Ofast -flto
# Linker flags to include the pre-compiled DSP math library and standard math functions
APP_LDFLAGS += -L$(DSP_LIB)/lib -lplpdsp -lm

# Include the standard PMSIS SDK build rules
include $(RULES_DIR)/pmsis_rules.mk
