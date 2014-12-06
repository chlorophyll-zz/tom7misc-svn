
var counter = 0, skipped = 0;
var start_time = (new Date()).getTime();

// Number of elapsed frames in the current scene.
var frames = 0;

/*
var resources = new Resources(
  [],
  [], null);
*/

function XY(x, y) { return '(' + x + ',' + y + ')'; }

function Init() {

  // Audio tweaks.
  // song_theme.multiply = 1.5;
  // song_power.multiply = 1.35;

  // song_menu[0].volume = 0.65;
}

function InitYouWin() {
  window.x = 0;
  window.y = 0
  window.c = 0
  window.u = 0;
}

InitYouWin();

function YouWin() {
  // ctx.fillStyle = 'rgba(0, 0, 0, 1)';
  // ctx.fillRect(0, 0, WIDTH, HEIGHT);
  u++;
  for (var i = 0; i < WIDTH * 2; i++) {
    x += u;
    y += x;
    x += 1;
    y += 5;
    x %= WIDTH;
    y %= HEIGHT;

    c += 3;
    c %= 256;

    ctx.fillStyle = 
	'rgba(' + Math.round((x / WIDTH) * 255) + ', ' + 
	Math.round(c) + ', 128, 0.1)';
    ctx.fillRect(x, y, x + 100, y + 100);
  }
}

function Static(x, y, w, h) {
  this.x = x;
  this.y = y;
  this.w = w;
  this.h = h;
  return this;
}

Static.prototype.x1 = function() { return this.x; }
Static.prototype.x2 = function() { return this.x + this.w; }
Static.prototype.y1 = function() { return this.y; }
Static.prototype.y2 = function() { return this.y + this.h; }
Static.prototype.DebugString = function() {
  return 'Static(' + [this.x, this.y, this.w, this.h].join(',') + ')';
}
Static.prototype.DrawCropped = function(d, osx1, osy1, osx2, osy2,
					sx1, sy1, sx2, sy2,
					fg, bg) {
  // Fortunately, rectangular clipping is easy. We just 
  // use min/max to snap the rectangles into the screen
  // space, which we know.

  var csx1 = Math.max(osx1, sx1);
  var csx2 = Math.min(osx2, sx2);
  var csy1 = Math.max(osy1, sy1);
  var csy2 = Math.min(osy2, sy2);

  ctx.fillStyle = fg;
  ctx.fillRect(csx1, csy1, csx2 - csx1, csy2 - csy1);
};

// All in world coordinates. This is the map itself, and
// these never move. 
var staticsquares = [
  // TODO import from illustrator or sth.
  new Static(0, 750, 1000, 50),
  new Static(200, 700, 100, 25)
];

function Dynamic(x, y, w, h, fg, bg) {
  // XXX also needs to know its viewport into the world, and
  // its control attenuation.
  this.x = x;
  this.y = y;
  this.w = w;
  this.h = h;
  this.fg = fg;
  this.bg = bg;
  return this;
}

Dynamic.prototype.x1 = function() { return this.x; }
Dynamic.prototype.x2 = function() { return this.x + this.w; }
Dynamic.prototype.y1 = function() { return this.y; }
Dynamic.prototype.y2 = function() { return this.y + this.h; }
Dynamic.prototype.DebugString = function() {
  return 'Dynamic(' + [this.x, this.y, this.w, this.h].join(',') + ')';
}
Dynamic.prototype.DrawCropped = function(d,
					 osx1, osy1, osx2, osy2,
					 sx1, sy1, sx2, sy2,
					 fg, bg) {
  // XXX get local values from object
  var wr = scale * ((osx2 - osx1) / WIDTH);
  // These may be updated if we crop.
  var wx = xpos;
  var wy = ypos;

  // cx/cy are the cropped screen coordinates.
  // We crop like anything, and the world ratio will stay the same
  // for the inner drawing. However, if we've chopped from the
  // top or left, then we need to pan the world to compensate.
  var cx1 = osx1;
  if (sx1 > osx1) {
    cx1 = sx1;
    wx += (sx1 - osx1) / wr;
  }

  var cy1 = osy1;
  if (sy1 > osy1) {
    cy1 = sy1;
    wy += (sy1 - osy1) / wr;
  }

  var cx2 = Math.min(osx2, sx2);
  var cy2 = Math.min(osy2, sy2);

  // We've become smaller than a pixel, which is the ultimate fate
  // of singularities.
  if ((cx2 - cx1) <= 1 &&
      (cy2 - cy1) <= 1) {
    ctx.fillStyle = '#FF0000';
    ctx.fillRect(cx1, cy1, 1, 1);
    return;
  }

  if (d > 25) {
    console.log('"infinite" recursion? ' +
		' os: ' + [osx1, osy1, osx2, osy2].join(',') +
		' s: ' + [sx1, sy1, sx2, sy2].join(',') +
		' cs: ' + [cx1, cy1, cx2, cy2].join(',') +
		' fg bg: ' + [fg, bg].join(','));
    ctx.fillStyle = '#000000';
    ctx.fillRect(cx1, cy1, cx2 - cx1, cy2 - cy1);
    return;
  }

  // console.log('rec drawworld: ' + newscale);
  DrawWorld(d + 1,
	    this.fg, this.bg,
	    cx1, cy1, cx2, cy2,
	    wx, wy, wr);

};


var dynamicobjects = [
  new Dynamic(215, 575, 100, 100, '#00FF00', '#333333'),
  new Dynamic(125, 600, 100, 100, '#FFCC00', '#556622')
];

function DrawWorld(
  // Depth, mainly for debugging..
  d,
  // Foreground and background colors.
  fg, bg,
  // Screen coordinates. We do need to do our own clipping.
  sx1, sy1, sx2, sy2,
  // World coordinates and scale factor
  wx1, wy1, wr) {

  // Coordinate transforms.
  var wxtosx = function(wx) {
    var wo = wx - wx1;
    var so = wo * wr;
    return Math.round(sx1 + so);
  };

  var wytosy = function(wy) {
    var wo = wy - wy1;
    var so = wo * wr;
    return Math.round(sy1 + so);
  };

  var wx2 = wxtosx(sx2);
  var wy2 = wytosy(sy2);

  var DO = function(obj) {
    // console.log('on screen? ' + XY(sx1, sy1) + ' to ' + XY(sx2, sy2));
    // console.log(obj.DebugString());
    
    // First, discard the object if it's completely 
    // outside our screen rectangle. We do all clipping
    // in screen coordinates, because we don't want
    // anything poking in/out one pixel on our nice
    // rectangles.
    var osx1 = wxtosx(obj.x1());
    if (osx1 > sx2) return;
    var osx2 = wxtosx(obj.x2());
    if (osx2 < sx1) return;
    var osy1 = wytosy(obj.y1());
    if (osy1 > sy2) return;
    var osy2 = wytosy(obj.y2());
    if (osy2 < sy1) return;

    // Objects only need to know where to draw themselves
    // on the screen, as well as the crop rectangle.
    obj.DrawCropped(d + 1, osx1, osy1, osx2, osy2,
		    sx1, sy1, sx2, sy2,
		    fg, bg);
  };

  // Start by drawing the background color in the entire
  // rectangle.
  ctx.fillStyle = bg;
  ctx.fillRect(sx1, sy1, sx2 - sx1, sy2 - sy1);

  for (var o in staticsquares) DO(staticsquares[o]);
  // And dynamic objects...
  for (var o in dynamicobjects) DO(dynamicobjects[o]);
}

var xpos = 50;
var ypos = 520;
var scale = 1.33;
// Bug here: 
//  var xpos =  50 , ypos =  370 , scale =  1.33 ;
function Draw() {
  DrawWorld(0, '#FFFFFF', '#0000FF',
	    0, 0, WIDTH, HEIGHT,
	    xpos, ypos, scale);
}

function DumpPos() {
  console.log('var xpos = ', xpos, ', ypos = ', ypos, ', scale = ', scale,
	      ';');
}

function Physics() {
  if (holdingLeft) xpos -= 10;
  else if (holdingRight) xpos += 1;
  if (holdingUp) ypos -= 10;
  else if (holdingDown) ypos += 1;
  if (holdingPlus) scale *= 1.1;
  else if (holdingMinus) scale /= 1.1;
}

last = 0;
function Step(time) {
  // Throttle to 30 fps or something we
  // should be able to hit on most platforms.
  // Word has it that 'time' may not be supported on Safari, so
  // compute our own. (TODO: use performance.now probably)
  var now = (new Date()).getTime();
  var diff = now - last;
  // debug.innerHTML = diff;
  // Don't do more than 30fps.
  // XXX This results in a frame rate of 21 on RIVERCITY, though
  // I can easily get 60, so what gives?
  if (diff < MINFRAMEMS) {
    skipped++;
    window.requestAnimationFrame(Step);
    return;
  }
  last = now;

  frames++;
  if (frames > 1000000) frames = 0;

  // UpdateSong();

  Physics();

  Draw();

  // process music in any state
  // UpdateSong();

  // On every frame, flip to 4x canvas
  bigcanvas.Draw4x(ctx);

  if (true || DEBUG) {
    counter++;
    var sec = ((new Date()).getTime() - start_time) / 1000;
    document.getElementById('counter').innerHTML =
        'skipped ' + skipped + ' drew ' +
        counter + ' (' + (counter / sec).toFixed(2) + ' fps)';
  }

  // And continue the loop...
  window.requestAnimationFrame(Step);
}

function Start() {
  Init();

  // StartSong(song_theme);

  window.requestAnimationFrame(Step);
}

var holdingLeft = false, holdingRight = false,
  holdingUp = false, holdingDown = false,
  holdingSpace = false, holdingEnter = false,
  holdingX = false, holdingZ = false,
  holdingPlus = false, holdingMinus = false;

document.onkeydown = function(e) {
  e = e || window.event;
  if (e.ctrlKey) return true;

  switch (e.keyCode) {
    case 9:
    // CHEATS
    if (true || DEBUG)
      textpages = [];
    break;
    case 27: // ESC
    if (true || DEBUG) {
      ClearSong();
      document.body.innerHTML =
	  '<b style="color:#fff;font-size:40px">(SILENCED. ' +
          'RELOAD TO PLAY)</b>';
      Step = function() { };
      // n.b. javascript keeps running...
    }
    case 8: // BACKSPACE
    if (DEBUG) {
      gang = null;
    }
    break;
    case 37: // LEFT
    holdingLeft = true;
    break;
    case 38: // UP
    holdingUp = true;
    break;
    case 39: // RIGHT
    holdingRight = true;
    break;
    case 40: // DOWN
    holdingDown = true;
    break;
    case 32: // SPACE
    holdingSpace = true;
    break;
    case 13: // ENTER
    holdingEnter = true;
    break;
    case 90: // Z
    holdingZ = true;
    break;
    case 88: // X
    holdingX = true;
    break;
    case 187: // +/=
    holdingPlus = true;
    break;
    case 189: // -/_
    holdingMinus = true;
    break;
    default:
    // console.log(e.keyCode);
  } 
  // var elt = document.getElementById('key');
  // elt && (elt.innerHTML = 'key: ' + e.keyCode);
  return false;
}

document.onkeyup = function(e) {
  e = e || window.event;
  if (e.ctrlKey) return true;

  switch (e.keyCode) {
    case 37: // LEFT
    holdingLeft = false;
    break;
    case 38: // UP
    holdingUp = false;
    break;
    case 39: // RIGHT
    holdingRight = false;
    break;
    case 40: // DOWN
    holdingDown = false;
    break;
    case 32: // SPACE
    holdingSpace = false;
    break;
    case 13: // ENTER
    holdingEnter = false;
    break;
    case 90: // Z
    holdingZ = false;
    break;
    case 88: // X
    holdingX = false;
    break;
    case 187: // +/=
    holdingPlus = false;
    break;
    case 189: // -/_
    holdingMinus = false;
  }
  return false;
}

// resources.WhenReady(Start);
Start();
