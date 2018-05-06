obj-m += gpio-pca953x.o

KDIR := "/lib/modules/$(shell uname -r)/build"

all:
	make -C "$(KDIR)" "M=$(PWD)" modules

clean:
	make -C "$(KDIR)" "M=$(PWD)" clean
