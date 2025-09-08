# Compiler and flags
ASM = rgbasm
LINK = rgblink
FIX = rgbfix
ASMFLAGS = -Wall
LINKFLAGS =
FIXFLAGS = -p 0xff

# Directories
SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = bin

SRCS = $(wildcard $(SRC_DIR)/*.asm)
OBJS = $(patsubst $(SRC_DIR)/%.asm, $(OBJ_DIR)/%.o, $(SRCS))

# ROM name
ROM = unbricked.gb

all: $(BIN_DIR)/$(ROM)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.asm | $(OBJ_DIR)
	$(ASM) $(ASMFLAGS) -o $@ $<

$(BIN_DIR)/$(ROM): $(OBJS) | $(BIN_DIR)
	$(LINK) $(LINKFLAGS) -o $@ $<
	$(FIX) $(FIXFLAGS) -v $@

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)

.PHONY: all clean