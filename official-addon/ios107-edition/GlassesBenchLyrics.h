#ifndef TURBO_GLASSES_BENCH_LYRICS_H
#define TURBO_GLASSES_BENCH_LYRICS_H
/* Demo lyric fixtures for the Glasses test bench (Developer, key testBench). Plain C so that the phone code and the host layout test
 * (tests/GlassesBenchLayout_test.c, which runs the firmware's own tm_fit_current over them) read the same text.
 *
 * X(id, lang, step, lines, ellipsis, nextEllipsis, current, next)
 *   step, lines   the fit step (firmware music_layout.h: 1 two 24 px lines, 2 up to four 24 px lines, 3 four 20 px lines,
 *                 4 five 16 px lines) and the wrapped row count the current lyric must land in after the 240 B clip.
 *   ellipsis      1 when the current lyric still ends in an ellipsis after the clip (only beyond step 4). A Latin line within 240 B fits five
 *                 16 px rows in lower case, so the ellipsis fixture is all capitals (wider glyphs) and longer than the cap, which also exercises the clip.
 *   nextEllipsis  1 when the next lyric is too wide for one 20 px row and ends in an ellipsis.
 * Every line is demo text written for this bench. A line is cut at TGB_LYRIC_CAP bytes before it is sent, like MusicBridge does. */
#define TGB_LYRIC_CAP 240u
#define TGB_LYRIC_POSITION_MS 5000u    /* paused here: the first line is the current one */
#define TGB_LYRIC_NEXT_MS 30000u
#define TGB_LYRIC_DURATION_MS 240000u
#define TGB_LONG "The morning light is falling on the streets we used to know and every window glows"
#define TGB_LYRICS(X) \
 X(en3,"en",2,3,0,0,TGB_LONG,"Hold on to the light") \
 X(en4,"en",2,4,0,0,TGB_LONG " with the stories of the city","Hold on to the light") \
 X(en4s,"en",3,4,0,0,TGB_LONG " with the stories of the city we have loved for years","Hold on to the light") \
 X(en5,"en",4,5,0,0,TGB_LONG " with the stories of the city we have loved for years and all the nights we sang along until the sun came up over the harbour","Hold on to the light") \
 X(enell,"en",4,5,1,0,"THE MORNING LIGHT IS FALLING ON THE STREETS WE USED TO KNOW AND EVERY WINDOW GLOWS WITH THE STORIES OF THE CITY WE HAVE LOVED FOR YEARS AND ALL THE NIGHTS WE SANG ALONG UNTIL THE SUN CAME UP OVER THE HARBOUR AND THE LONG ROAD HOME STILL WAITS FOR US BEYOND THE BRIDGE","Hold on to the light") \
 X(ennext,"en",1,1,0,1,"The morning light","Streets of gold and silver rivers running through the evening light of every city we have ever known") \
 X(zh3,"zh",2,3,0,0,/*i18n:keep*/"晨光落在我们曾经走过的街道上，每一扇窗都亮起了故事，风把旧时光轻轻吹回我的身旁","把这一刻留给我") \
 X(zh4,"zh",2,4,0,0,/*i18n:keep*/"晨光落在我们曾经走过的街道上，每一扇窗都亮起了故事，风把旧时光轻轻吹回我的身旁，我们并肩坐在河边的长椅上，一直唱到天亮","把这一刻留给我")
#endif
