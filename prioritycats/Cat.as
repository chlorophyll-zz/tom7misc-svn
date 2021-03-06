import flash.display.*;
import flash.geom.Matrix;
/* Used to be 'you', but now the game loop is
   done by LaserPointer since there are two
   cats. This just takes care of the animation
   and stuff. */
class Cat extends PhysicsObject {

  #include "constants.js"
  #include "frames.js"

  var dx = 0;
  var dy = 0;

  // Size of graphic, in world pixels.
  var width = 100;
  var height = 50;

  // Subtracted from clip region.
  // Player's top-left corner is at x+left, y+top.
  var top = 6;
  var left = 6;
  var right = 6;
  var bottom = 6;

  var FPS = 25;

  static var KIND_ORANGE = 1;
  static var KIND_GREY = 2;
  var kind;

  var frames, heads;

  // XXX shouldn't be squares, but...
  public function ignoresquares() {
    return true;
  }

  public function init(k) {
    kind = k;
    var pfx = (k == KIND_GREY) ? 'g' : '';
    // initialize frame data, by loading the bitmaps and
    // doing the flippin.
    frames = {};
    for (var o in framedata) {
      // Copy frames into L and R.
      frames[o] = { l: [],
                    r: [],
                    div: framedata[o].div || 8 };
      var f = framedata[o].f;
      for (var i = 0; i < f.length; i++) {
        var bm = BitmapData.loadBitmap(pfx + f[i].p + '.png');
        if (!bm) {
          trace('could not load bitmap ' + f[i].p +
                '. add it to the library and set linkage!');
        }
        frames[o].r.push({ bm: bm, hx : f[i].hx, hy: f[i].hy });

        var fliphoriz = new Matrix();
        fliphoriz.scale(-1,1);
        fliphoriz.translate(bm.width, 0);

        var fbm = new BitmapData(bm.width, bm.height, true, 0);
        fbm.draw(bm, fliphoriz);
        // off-by-one in head x calc?
        // trace('hx: ' + ((width / 2) - f[i].hx));
        frames[o].l.push({ bm: fbm, hx : (width / 2) - f[i].hx, hy: f[i].hy });
      }
    }

    heads = {};
    // Same for heads. Code reuse!
    for (var o in headdata) {
      // Copy frames into L and R.
      heads[o] = { l: [],
                   r: [],
                   div: headdata[o].div || 8 };
      var f = headdata[o].f;
      for (var i = 0; i < f.length; i++) {
        var bm = BitmapData.loadBitmap(pfx + f[i] + '.png');
        if (!bm) {
          trace('could not load bitmap ' + f[i] +
                '. add it to the library and set linkage!');
        }
        heads[o].r.push({ bm: bm });

        var fliphoriz = new Matrix();
        fliphoriz.scale(-1,1);
        fliphoriz.translate(bm.width, 0);

        var fbm = new BitmapData(bm.width, bm.height, true, 0);
        fbm.draw(bm, fliphoriz);
        // off-by-one in head x calc?
        heads[o].l.push({ bm: fbm });
      }
    }

  }

  // Keep track of what dudes I touched, since
  // I don't want triple point tests or iterated
  // adjacency to make lots of little pushes.
  var touchset;
  public function touch(other : PhysicsObject) {
    for (var o in touchset) {
      if (touchset[o] == other)
        return;
    }
    touchset.push(other);
  }

  public function onLoad() {
    touchset = [];
    Key.addListener(this);
    this._xscale = 200.0;
    this._yscale = 200.0;
    // Doesn't really matter which one is on top. Try both.
    this.setdepth(CATDEPTH + 1);
    this.setdepth(CATDEPTH);
    this.stop();
  }

  public function getConstants() {
    var C = defaultconstants();
    if (kind == KIND_ORANGE) {
      // A little bit faster.
      C.maxspeed = 11.1;
      C.jump_impulse = 17.7;
      // Can control himself in the air better.
      C.accel_air = 0.3;
      C.decel_air = 0.045;
    } else if (kind == KIND_GREY) {
      // A little bit slower and fatter.
      C.accel = 3.3;
      C.terminal_velocity = 14.4;
    }
    return C;
  }

  var wanna_jump = false;
  var wanna_left = false;
  var wanna_right = false;

  var paralyzed = false;  // XXX
  public function wishjump() {
    return !paralyzed && wanna_jump;
  }

  public function wishleft() {
    return !paralyzed && wanna_left;
  }

  public function wishright() {
    return !paralyzed && wanna_right;
  }

  public function wishdive() {
    return false;
  }
  
  var looking = false;
  var lookx = 0, looky = 0;
  
  // Used by orange cat to test that the
  // dot hasn't moved too quickly.
  var lastlookx = 1, lastlooky = 1;
  var stationary_count = 0;
  var moving = false;

  public function lookat(x, y) {
    looking = true;
    lookx = x;
    looky = y;

    // Always compute this. Note we use
    // the center of the cat to make physics
    // invariant to the cat's current direction,
    // though the head's rotation (merely presentational)
    // is based on its display location.
    var cx = this._x + width / 2;
    var cy = this._y + height / 2;

    var rads = Math.atan2(y - cy, x - cx);
    var degs = (360 + rads * 57.2957795) % 360;
    // Made this table with the wrong handedness.
    degs = 360 - degs;

    if (this.kind == KIND_ORANGE) {
      // Orange cat moves towards the laser,
      // but when he's resting, he needs the
      // laser to be stationary for ~750ms
      // before he'll chase it.
      if (!moving) {
        if (Math.abs(lookx - lastlookx) < 2 &&
            Math.abs(looky - lastlooky) < 2) {
          stationary_count++;
          // trace('stationary for ' + stationary_count);
          if (stationary_count > ORANGE_STATIONARY_FRAMES) {
            moving = true;
          }
        } else {
          stationary_count = 0;
        }
        lastlookx = lookx;
        lastlooky = looky;
      }

      if (moving) {
        wanna_right = (degs <= 60 || degs >= 300);
        wanna_left = (degs >= 120 && degs <= 240);
        // Must it be mutually exclusive?
        // Not only in the correct angle, but not too
        // close to the cat's head. (But don't apply if
        // the cursor is in the top row, since we want to
        // make it easier to jump to the room above.)
        wanna_jump = (y < 50 || (cy - y > 75)) && (degs >= 60 && degs <= 120);
      }

    } else if (this.kind == KIND_GREY) {
      // XXX grey cat needs to have some special
      // characteristics too. maybe?

      wanna_right = (degs <= 60 || degs >= 300);
      wanna_left = (degs >= 120 && degs <= 240);
      wanna_jump = (y < 50 || (cy - y > 75)) && (degs >= 60 && degs <= 120);
    }
  }

  // Both cats immediately go to sleep and become
  // deadweight if they stop seeing the laser.
  public function nolook() {
    looking = false;
    wanna_left = false;
    wanna_right = false;
    wanna_jump = false;
    // Can't see laser; this doesn't count as stationary.
    lastlookx = -1;
    lastlooky = -1;
    stationary_count = 0;
    // Orange cat instantly goes asleep.
    moving = false;
  }

  var framemod : Number = 0;
  var facingright = true;
  public function onEnterFrame() {
    // Avoid overflow at the expense of jitter.
    framemod++;
    if (framemod > 100000)
      framemod = 0;

    touchset = [];

    movePhysics();

    // Now, if we touched someone, give it some
    // love.
    for (var o in touchset) {
      var other = touchset[o];

      // This is where I activate touchable things.

      var diffx = other._x - this._x;
      var diffy = other._y - this._y;

      var normx = diffx / width;
      var normy = diffy / height;

      // Don't push from side to side when like
      // standing on a dude but not centered.
      if (Math.abs(normx) > Math.abs(normy)) {
        other.dx += normx;
      } else {
        other.dy += normy;
      }
    }

    // Make sure we're not interfering with the message.
    /*
    if (this._y < 130) {
      _root.message._y = (290 + _root.message._y) / 2;
    } else {
      _root.message._y = (14 + _root.message._y) / 2;
    }
    */

    var what_stand = 'buttup', what_jump = 'jump';

    if (Math.abs(dx) > 9)
      what_stand = 'run';
    
    if (!looking)
      what_stand = 'rest';

    // true means force animation, even if still
    var what_animate = false;

    var otg = ontheground();
    if (otg) {

      // If I can't see the laser, and I'm on the ground, 
      // then I'm resting.
      if (dx > 1) {
        facingright = true;
        setframe(what_stand, facingright, framemod);
      } else if (dx > 0) {
        facingright = true;
        setframe(what_stand, facingright, what_animate ? framemod : 0);
      } else if (dx < -1) {
        facingright = false;
        setframe(what_stand, facingright, framemod);
      } else if (dx < 0) {
        setframe(what_stand, facingright, what_animate ? framemod : 0);
      } else {
        // standing still on ground. Animate the butt pose if
        // we've been staring at a stationary dot for long enough.
        what_animate = what_animate || stationary_count > 1;

        setframe(what_stand, facingright, what_animate ? framemod : 0);
      }
      // ...
    } else {
      // In the air.
      setframe(what_jump, facingright, framemod);
    }

    // n.b. the laser controls room transitions, to make sure that
    // both cats don't initiate one in the same frame!
  }

  var body: MovieClip = null, head: MovieClip = null;
  public function setframe(what, fright, frmod) {

    // PERF don't need to do this if we're already on the
    // right frame, which is the common case.
    if (body) body.removeMovieClip();
    body = this.createEmptyMovieClip('body',
                                     this.getNextHighestDepth());
    body._x = 0;
    body._y = 0;

    // Facing left or right?
    var fs = (fright ? frames[what].r : frames[what].l);
    // XXX pingpong
    var f = int(frmod / frames[what].div) % fs.length;
    // trace(what + ' ' + frmod + f);
    // trace('' + fs[f].bm + ' ?');
    body.attachBitmap(fs[f].bm, body.getNextHighestDepth());

    // Figure out which head, based on the angle to the laser.
    // We calculate it here because we know where the head
    // is actually attached, so we can get the most accurate
    // reading.
    var whathead;
    if (looking) {
      var cx = (fs[f].hx * 2) + this._x;
      var cy = (fs[f].hy * 2) + this._y;
      var dx = lookx - cx;
      var dy = looky - cy;

      if (dx == 0 && dy == 0) {
        // Also should be this in the no-head case?
        // Also should be headw if facing left?
        whathead = 'heade';
      } else {
        var rads = Math.atan2(dy, dx);
        var degs = (360 + rads * 57.2957795) % 360;

        // Made this table with the wrong handedness.
        degs = 360 - degs;

        // _root.message.text = '' + int(degs) + ' ' + dx + ' ' + dy;
        // _root.message.swapDepths(99999);

        if (degs >= 330 || degs < 30) {
          whathead = 'heade';
        } else if (degs <= 60) {
          whathead = 'headne';
        } else if (degs <= 90) {
          whathead = 'headnne';
        } else if (degs >= 300) {
          whathead = 'headse';
        } else if (degs >= 270) {
          whathead = 'headsse';
        } else if (degs >= 240) {
          whathead = 'headssw';
        } else if (degs >= 210) {
          whathead = 'headsw';
        } else if (degs <= 120) {
          whathead = 'headnnw';
        } else if (degs <= 150) {
          whathead = 'headnw';
        } else {
          whathead = 'headw';
        }
      }
    } else {
      whathead = 'headrest';
    }

    // reverse head if reversed.
    if (!fright) whathead = reverseHead(whathead);

    if (head) head.removeMovieClip();
    // has to be on top of body
    head = this.createEmptyMovieClip('head',
                                     this.getNextHighestDepth());
    head._x = fs[f].hx - HEADATTACHX;
    head._y = fs[f].hy - HEADATTACHY;

    var fs = (fright ? heads[whathead].r : heads[whathead].l);
    var f = int(frmod / heads[whathead].div) % fs.length;
    // trace(whathead + ' ' + fs + ' ' + f);
    head.attachBitmap(fs[f].bm, body.getNextHighestDepth());
  }

}
