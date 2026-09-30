/* All inputs use the target window's DPI coordinate space, never a separately
 * forced screen backing ratio. Work area, chrome, design and footer must agree. */
static int launcher_fit_percent(int requested,int width,int height,int footer,
                                int workw,int workh,int borderw,int borderh,int margin) {
    int fitw=(workw-margin-borderw)*100/width;
    int fith=(workh-margin-borderh)*100/(height+footer);
    // Automatic starts at the full design size and shrinks only to fit.
    int percent=requested?requested:100;
    if(percent>fitw)percent=fitw;
    if(percent>fith)percent=fith;
    if(percent<10)percent=10;
    if(percent>125)percent=125;
    return percent;
}
