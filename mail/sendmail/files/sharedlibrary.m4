divert(0)dnl
include(confBUILDTOOLSDIR`/M4/'bldM4_TYPE_DIR`/links.m4')dnl
bldLIST_PUSH_ITEM(`bldC_PRODUCTS', bldCURRENT_PRODUCT)dnl
bldPUSH_TARGET(bldCURRENT_PRODUCT.so.confSOVER)dnl
bldPUSH_INSTALL_TARGET(`install-'bldCURRENT_PRODUCT)dnl
bldPUSH_CLEAN_TARGET(bldCURRENT_PRODUCT`-clean')dnl

include(confBUILDTOOLSDIR`/M4/'bldM4_TYPE_DIR`/defines.m4')
divert(bldTARGETS_SECTION)

bldCURRENT_PRODUCT.so.confSOVER: ${BEFORE} ${bldCURRENT_PRODUCT`OBJS'}
	${CC} ${LDOPTS_SO} -o bldCURRENT_PRODUCT.so.confSOVER confSONAME,bldCURRENT_PRODUCT.so.confSOVER ${bldCURRENT_PRODUCT`OBJS'}
ifdef(`bldLINK_SOURCES', `bldMAKE_SOURCE_LINKS(bldLINK_SOURCES)')

install-`'bldCURRENT_PRODUCT: bldCURRENT_PRODUCT.so.confSOVER

ifdef(`bldINSTALLABLE', `	ifdef(`confMKDIR', `if [ ! -d ${DESTDIR}${LIBDIR} ]; then confMKDIR -p ${DESTDIR}${LIBDIR}; else :; fi ')
	${LN} ${LNOPTS} bldCURRENT_PRODUCT.so.confSOVER ${DESTDIR}${LIBDIR}/bldCURRENT_PRODUCT.so
	${INSTALL} -c -m 644 bldCURRENT_PRODUCT.so.confSOVER ${DESTDIR}${LIBDIR}')

bldCURRENT_PRODUCT-clean:
	rm -f ${OBJS} bldCURRENT_PRODUCT.so* ${MANPAGES}

divert(0)
COPTS+= confCCOPTS_SO
