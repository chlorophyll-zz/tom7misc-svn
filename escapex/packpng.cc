#include "escapex.h"
#include "level.h"
#include "../cc-lib/sdl/sdlutil.h"

#include "util.h"
#include "font.h"
#include "draw.h"

#include <iostream>
#include <fstream>
#include <memory>

/* XXX necessary? */
SDL_Surface *screen;
string self;

#define BACKCOLOR 0x33, 0x88, 0x33, 0xAA

/* smaller growrate gives slightly better output,
   with substantially worse performance */
#define GROWRATE 4

struct UsedMap {
  /* PERF could use less memory with a bit mask,
     but this program is run off-line, so that
     seems pretty pointless */
  char *arr;
  int w, h;

  UsedMap(int ww, int hh) : w(ww), h(hh) {
    arr = (char*)malloc(ww * hh * sizeof(char));
    memset(arr, 0, ww * hh * sizeof (char));
  }

  /* new areas are unused */
  void resize(int ww, int hh) {
    char *na = (char*)malloc(ww * hh * sizeof (char));

    /* start unused */
    memset(na, 0, ww * hh * sizeof (char));

    /* copy old used */
    for (int xx = 0; xx < w; xx++) {
      for (int yy = 0; yy < h; yy++) {
        if (used(xx, yy) && xx < ww && yy < hh) {
          na[yy * ww + xx] = 1;
        }
      }
    }

    free(arr);
    arr = na;
    w = ww;
    h = hh;
  }

  bool used(int x, int y) {
    return arr[x  + y * w];
  }

  bool usedrange(int x, int y, int ww, int hh) {
    for (int yy = 0; yy < hh; yy++) {
      for (int xx = 0; xx < ww; xx++) {
        if (used(x + xx, y + yy)) return true;
      }
    }
    return false;
  }

  void use(int x, int y) {
    arr[x + y * w] = 1;
  }

  void userange(int x, int y, int ww, int hh) {
    for (int yy = 0; yy < hh; yy++) {
      for (int xx = 0; xx < ww; xx++) {
        use(x + xx, y + yy);
      }
    }
  }

  ~UsedMap() {
    free(arr);
  }
};

static void fit_image(SDL_Surface *&packed, UsedMap *um,
                      int w, int h,
                      int &x, int &y) {
  for (;;) {
    for (int yy = 0; yy <= um->h - h; yy++) {
      for (int xx = 0; xx <= um->w - w; xx++) {
        if (!um->usedrange(xx, yy, w, h)) {
          um->userange(xx, yy, w, h);
          x = xx;
          y = yy;
          return;
        }
      }
    }

    /* didn't fit. expand to make the image more square. */
    /* PERF insane */
    int nw = um->w, nh = um->h;

    /* minimum sane sizes */
    if (um->w < w) {
      nw = w;
    } else if (um->h < h) {
      nh = h;
    } else if (um->w <= um->h) {
      nw = um->w + GROWRATE;
    } else {
      nh = um->h + GROWRATE;
    }

    um->resize(nw, nh);
    // XXX byte order
    SDL_Surface *n = sdlutil::resize_canvas(packed, nw, nh,
                                            SDL_MapRGBA(packed->format,
                                                        BACKCOLOR));
    SDL_FreeSurface(packed);
    packed = n;

    printf("resized to %dx%d\n", nw, nh);
  }
}


int main(int argc, char **argv) {

  /* change to location of binary, so that we can find the
     images needed. */
  if (argc > 0) {
    string wd = util::pathof(argv[0]);
    util::changedir(wd);

#   if WIN32
    /* on win32, the ".exe" may or may not
       be present. Also, the file may have
       been invoked in any CaSe. */
    self = util::lcase(util::fileof(argv[0]));
                    self = util::ensureext(self, ".exe");
#   else
                    self = util::fileof(argv[0]);
#   endif

  }

  if (argc != 3) {
    printf("\n"
           "Usage: packpng description.pack basename\n");
    printf("Creates a packed PNG graphic from each of the files in\n"
           "description.pack. Produces:\n"
           "   basename.png    (graphics)\n"
           "   basename_defs.h (defines variables in class)\n"
           "   basename_decs.h (declares the members as basename::pic)\n"
           "   basename_load.h (code that loads the graphics)\n"
           "\n"
           "See packpng.cc for details.\n\n");
    return 1;
  }

  /* we don't really need any SDL modules */
  if (SDL_Init (SDL_INIT_NOPARACHUTE) < 0) {
    printf("Unable to initialize SDL. (%s)\n", SDL_GetError());
    return 1;
  }


  string descname = argv[1];
  string basename = argv[2];

  printf("Packpng %s %s\n", descname.c_str(), basename.c_str());

  /* XXX we should make this part much smarter once
     we have a lot of animation frames or graphics of
     different sizes. The problem is probably NP hard
     in general but we can still do a better job with
     some greedy packing algorithm (keep a bit mask of
     'used' areas of the graphic) */

  /* now a single pass, resizing the destination image
     as needed. */

  SDL_Surface *packed = sdlutil::makesurface(1, 1);
  sdlutil::clearsurface(packed, BACKCOLOR);
  std::unique_ptr<UsedMap> um(new UsedMap{1, 1});

  if (!packed) {
    printf("Can't make initial surface\n");
    return -1;
  }

  string name, file;

  /* now draw 'em */

  string defname  = basename + "_defs.h";
  string decname  = basename + "_decs.h";
  string loadname = basename + "_load.h";
  FILE *defs = fopen(defname.c_str(), "w");
  FILE *decs = fopen(decname.c_str(), "w");
  FILE *load = fopen(loadname.c_str(), "w");

  if (!(defs && decs && load)) {
    printf("Can't open output files.\n");
    return -1;
  }

  /* load needs some prelude */
  fprintf(load,
          "/* Generated by packpng from %s. DO NOT EDIT */\n"
          "{\n"
          "  SDL_Surface *all = sdlutil::LoadImage(DATADIR \"%s.png\");\n"
          "  if (!all) return false;\n"
          "  SDL_SetAlpha(all, 0, 255);\n"
          "  SDL_Rect r;\n",
          descname.c_str(),
          basename.c_str());

  fprintf(defs,
          "/* Generated by packpng from %s. DO NOT EDIT */\n",
          descname.c_str());

  fprintf(decs,
          "/* Generated by packpng from %s. DO NOT EDIT */\n",
          descname.c_str());

  int cx = 0;
  {
    ifstream desc(descname.c_str());
    while (desc >> name >> file) {
      SDL_Surface *pic = sdlutil::LoadImage(file.c_str());

      if (!pic) {
        printf("Packpng error! Can't open image file '%s'\n",
                file.c_str());
        exit(-1);
      }

      /* turn off source alpha. Otherwise, we'll
         be blending against the background here */
      SDL_SetAlpha(pic, 0, 255);

      /* find a place where it will fit. */
      {
        int x, y;
        fit_image(packed, um, pic->w, pic->h, x, y);

        SDL_Rect rd;
        rd.x = x;
        rd.y = y;

        SDL_BlitSurface(pic, 0, packed, &rd);

        /* now print info to files */
        fprintf(defs, "static SDL_Surface *%s;\n", name.c_str());
        fprintf(decs, "SDL_Surface *%s::%s;\n",
                basename.c_str(), name.c_str());

        fprintf(load,
                "\n"
                "  r.x = %d;\n"
                "  r.y = %d;\n"
                "  r.w = %d;\n"
                "  r.h = %d;\n"
                "  %s = sdlutil::makesurface(r.w, r.h);\n"
                "  if (!%s) return false;\n"
                "  SDL_BlitSurface(all, &r, %s, 0);\n",
                x, y, pic->w, pic->h, name.c_str(),
                name.c_str(), name.c_str());

        printf("%s at %d/%d\n", name.c_str(), x, y);
      }

    }
  }

  /* postlude for load */
  fprintf(load,
          "\n\n"
          "  SDL_FreeSurface(all);\n"
          "}\n");

  fclose(load);
  fclose(defs);
  fclose(decs);

  printf("Saving...\n");
  fflush(stdout);

  const string pngfile = basename + ".png";
  if (!sdlutil::SavePNG(pngfile, packed)) {
    printf("Couldn't write output PNG to %s.\n", pngfile.c_str());
    return -1;
  }

  /* clean up and exit */

  SDL_FreeSurface(packed);

  printf("Done!\n");


  return 0;
}
