DASM_BIN_PATH=../../../dasm/bin/dasm
DASM_INCLUDE_PATH=../../../dasm/machines/atari2600/
ROM_PATH=/mnt/d/games/atari2600
PYTHON_BIN_PATH=/usr/bin/python
ROM_NAME=moosemaze.bin

ogam_jan_2016: 
	cat main.asm > moosemaze.asm
	$(PYTHON_BIN_PATH) mapmaker.py >> moosemaze.asm
	cat footer.asm >> moosemaze.asm
	$(DASM_BIN_PATH) moosemaze.asm -s$(ROM_PATH)/moosemaze.sym -l$(ROM_PATH)/moosemaze.lst -I$(DASM_INCLUDE_PATH) -I. -f3 -v5 -o$(ROM_PATH)/$(ROM_NAME)