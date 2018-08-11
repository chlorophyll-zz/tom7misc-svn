
let counter = 0, skipped = 0;
let start_time = (new Date()).getTime();

let mousex = 0;
let mousey = 0;

// no y-scrolling.
let scrollx = 400;

// Number of elapsed frames in the current scene.
let frames = 0;

// If null, no active sentence.
// Otherwise, we have
//  { verb: (one of the VERB enums)
//    obj1: (use OBJ1 with OBJ2)
//    obj2: (if necessary) }
// obj can be Ent or Item, or ...

let sentence = null;

const resources = new Resources(
  ['font.png',
   'spacefont.png',
   'title.png',
   'background.png',

   'ship.png',
   
   'face-right.png',
   'face-right-blink.png',
   'player1.png',
   'player2.png',
   'player3.png',

   'grateguy.png',
   
   'inv-icon.png',
   'inventory.png',
   'inv-used.png',

   'id.png',
   'airlocktool.png',
   
   'invid.png',
   'invairlocktool.png',
   'invegg.png',
  ],
  [], null);

function XY(x, y) { return '(' + x + ',' + y + ')'; }

const STARCOLORS = [
  // B G R
  0xFFFFFF,
  0x00FFFF,
  0xFFFF00,
  0xFF0000,
  0xFFAAAA,
  0xAAFFFF
];

function Init() {
  window.font = new Font(resources.Get('font.png'),
                         FONTW, FONTH, FONTOVERLAP, FONTCHARS);
  window.hifont = new Font(
    EzRecolor(resources.Get('font.png'), 0xFFFFFFFF, 0xFF00FFFF),
    FONTW, FONTH, FONTOVERLAP, FONTCHARS);
  
  window.spacefont = new Font(resources.Get('spacefont.png'),
                              FONTW, FONTH, FONTOVERLAP, FONTCHARS);
  window.hispacefont = new Font(
    EzRecolor(resources.Get('spacefont.png'), 0xFFFFFFFF, 0xFF00FFFF),
    FONTW, FONTH, FONTOVERLAP, FONTCHARS);
  
  window.titleframes = Static('title.png');
  window.background = Static('background.png');
  let ship = resources.Get('ship.png');
  window.topdeckbg = new Frames(EzCropY(ship, 0, TOPDECKH));
  window.botdeckbg = new Frames(EzCropY(ship, TOPDECKH, 200 - TOPDECKH));

  window.starframes = [];
  for (let i = 0; i < 16; i++) {
    window.starframes.push(new EzStar(STARCOLORS[i % STARCOLORS.length]));
  }
  
  // UI elements
  window.inv_icon = EzFrames(['inv-icon', 1]);
  window.inventory = EzFrames(['inventory', 1]);
  window.invused = EzFrames(['inv-used', 1]);
  
  // window.playerr = FlipFramesHoriz(window.playerl);
  // window.playerr_run = FlipFramesHoriz(window.playerl_run);
  
  // Audio tweaks.
  // song_theme.multiply = 1.5;
  // song_power.multiply = 1.35;

  // song_menu[0].volume = 0.65;
}

// Item that can go in inventory.
function Item(name, invframes, worldframes, mask) {
  this.name = name;
  // Frames when in inventory
  this.invframes = EzFrames(invframes);
  this.worldframes = EzFrames(worldframes);
  this.mask = mask;
  
  // Position of top-left in inventory, or null if detached
  this.invx = null;
  this.invy = null;

  // Position in world (global coordinates, not screen), or null.
  // (Position is of top-left coordinate)
  // Can't have both world position and inventory position,
  // but an unspawned item could have both be null.
  this.worldx = null;
  this.worldx = null;

  // width/height in world. derived from first frame.
  this.worldw = this.worldframes.width;
  this.worldh = this.worldframes.height;
  
  // TODO: state it goes back to if dropped?
  
  return this;
}

Item.prototype.MaskAt = function(x, y) {
  if (x < 0 || y < 0) return false;
  let row = this.mask[y] || '';
  let cell = row[x] || ' ';
  return cell != ' ';
};

function InitGame() {

  scrollx = 5 * WIDTH;
  
  window.phase = PHASE_GAME;

  window.ents = {};
  window.ents.grateguy = new Ent('ALIEN',
				 ['grateguy', 1],
				 // no moving anim
				 ['grateguy', 1],
				 30, 65);
  window.ents.grateguy.worldx = 1140;
  window.ents.grateguy.worldy = 91;

  window.player = new Ent('ME',
			  ['player1', 1],
			  ['player1', 9,
			   'player2', 2,
			   'player3', 6,
			   'player2', 2],
			  68,
			  46);
  player.worldx = WIDTH * 5 + 122;
  player.worldy = 160;
  player.facer = EzFrames(['face-right', 280,
			   'face-right-blink', 2,
			   'face-right', 68,
			   'face-right-blink', 2]);
  player.facel = FlipFramesHoriz(player.facer);
  player.Draw = function(x, y) {
    this.SuperDraw(x, y);
    DrawFrame(this.facingleft ? this.facel : this.facer,
	      x + (this.facingleft ? LFACEX : FACEX), y + FACEY);
  };
		       
  window.ents.player = window.player;
		       
  const MASK2x2 = ['**',
		   '**'];
  const MASK1x1 = ['*'];

  window.inventoryopen = false;

  window.items = {};
  window.items.egg1 = new Item('EGG', ['invegg', 1], ['invegg', 1], MASK2x2);
  window.items.egg2 = new Item('EGG', ['invegg', 1], ['invegg', 1], MASK2x2);
  window.items.egg3 = new Item('EGG', ['invegg', 1], ['invegg', 1], MASK2x2);
  window.items.egg4 = new Item('EGG', ['invegg', 1], ['invegg', 1], MASK2x2);

  // Start with four eggs
  window.items.egg1.invx = 0;
  window.items.egg1.invy = 0;
  window.items.egg2.invx = 2;
  window.items.egg2.invy = 0;
  window.items.egg3.invx = 4;
  window.items.egg3.invy = 0;
  window.items.egg4.invx = 6;
  window.items.egg4.invy = 0;
  
  window.items.airlocktool = new Item('TOOL',
				      ['invairlocktool', 1],
				      ['airlocktool', 1],
				      [' **',
				       ' * ',
				       '** ']);

  window.items.airlocktool.worldx = 80;
  window.items.airlocktool.worldy = 48;
  
  window.items.id = new Item('CARD',
			     ['invid', 1],
			     ['id', 1],
			     MASK1x1);

  window.items.id.worldx = WIDTH * 5 + 30;
  window.items.id.worldy = 140;
  
  console.log('initialized game');
}

// Entity in game that can walk around, speak, etc.
// Includes the player character.
function Ent(name, stand, move, wd, ht) {
  this.name = name;
  
  this.halfwidth = wd >>> 1;
  this.height = ht;

  this.xspeed = 2;
  this.yspeed = 1;
  
  // If non-null, location in the world.
  this.worldx = null;
  this.worldy = null;

  // If non-null, we're walking to this target spot.
  this.targetx = null;
  this.targety = null;

  // Current frames.
  this.standr = EzFrames(stand);
  this.standl = FlipFramesHoriz(this.standr);

  this.mover = EzFrames(move);
  this.movel = FlipFramesHoriz(this.mover);

  this.facingleft = false;
  
  return this;
}

Ent.prototype.GetFrames = function() {
  const moving = this.targetx != null &&
	(this.worldx != this.targetx ||
	 this.worldy != this.targety);
  
  if (this.facingleft)
    return moving ? this.movel : this.standl;
  else
    return moving ? this.mover : this.standr;
};
  
Ent.prototype.SuperDraw = function(x, y) {
  const f = this.GetFrames();
  DrawFrame(f, x, y);
};

// passed top-left corner (y - height).
Ent.prototype.Draw = function(x, y) {
  this.SuperDraw(x, y);
};
  
// Returns null if nothing, otherwise, the item.
function InvUsed(x, y) {
  for (let i in items) {
    let item = items[i];
    if (item.invx != null) {
      if (item.MaskAt(x - item.invx, y - item.invy))
	return item;
    }
  }
  return false;
}

let stars = [];

function SpawnStar() {
  return {x: GAMEWIDTH, y : 0 | (Math.random() * (HEIGHT - 1)),
	  // Not integral
	  dx: -0.1 + (Math.random() * -4.0) };
}

function DrawStars() {
  for (let i = 0; i < stars.length; i++) {
    let star = stars[i];
    if (star) {
      let x = (0 | star.x) - scrollx;
      if (x >= 0 && x < WIDTH) {
	DrawFrame(window.starframes[i % window.starframes.length],
		  x, star.y);
      }
    }
  }
}
function UpdateStars() {
  for (let i = 0; i < stars.length; i++) {
    if (stars[i] == null) {
      stars[i] = SpawnStar();
    } else {
      let star = stars[i];
      star.x += star.dx;
      if (star.x < 0)
	stars[i] = null;
    }
  }
}

function InitStars() {
  for (let i = 0; i < MAXSTARS; i++) {
    let star = SpawnStar();
    star.x = Math.random() * GAMEWIDTH;
    star.dx = -0.1 + (Math.random() * -4.0);
    stars.push(star);
  }
}

function DrawItemsWhen(cond) {
  // Draw items in the world.
  for (let o in items) {
    let item = items[o];
    if (item.worldx != null && cond(item)) {
      DrawFrame(item.worldframes,
		item.worldx - scrollx,
		item.worldy);
    }
  }
}

function DrawEntsWhen(cond) {
  for (let o in ents) {
    let ent = ents[o];
    if (ent.worldx != null && cond(ent)) {
      ent.Draw(ent.worldx - ent.halfwidth - scrollx,
	       ent.worldy - ent.height);
    }
  }
}

function ExtendSentence(noun) {
  if (sentence == null) {
    return { verb: VERB_LOOK, obj1 : noun, obj2 : null };
  } else if (sentence.obj1 == null) {
    return { verb: sentence.verb, obj1 : noun, obj2 : null };
  } else {
    if (sentence.verb == VERB_OVO ||
	sentence.verb == VERB_USE && sentence.obj2 == null) {
      return { verb: sentence.verb, obj1 : sentence.obj1, obj2 : noun };
    }
  }
}

// Draw the sentence (argument) at the top of the screen.
// Note this is also used when hovering, which happens before
// the sentence is actually saved.
function DrawSentence(s) {
  if (s == null) return;
  // Nice to show this with colors since it's in space language :)
  let ll = [];
  let OneObject = (v) => {
    if (s.obj1 != null)
      return [v, s.obj1.name];
    else
      return [v];
  };

  let TwoObjects = (v, c) => {
    if (s.obj2 != null)
      return [v, s.obj1.name, c, s.obj2.name];
    else if (s.obj1 != null)
      return [v, s.obj1.name, c];
    else
      return [v];
  };

  switch(s.verb) {
  case VERB_LOOK: ll = OneObject("LOOK AT"); break;
  case VERB_GRAB: ll = OneObject("GRAB"); break;
  case VERB_TALK: ll = OneObject("TALK TO"); break;
  case VERB_OVO: ll = TwoObjects("OVOPOSIT", "INTO"); break;
  case VERB_USE: ll = TwoObjects("USE", "WITH"); break;
  case VERB_DROP: ll = OneObject("DROP"); break;
  }

  let x = 1;
  for (let i = 0; i < ll.length; i++) {
    let ph = ll[i];
    ((i % 0 == 1) ? hifont : font).Draw(ctx, x, 1, ph);
    x += (ph.length + 1) * (FONTW - FONTOVERLAP);
  }
}

function DrawGame() {
  ClearScreen();
  DrawStars();

  DrawFrame(window.botdeckbg, -scrollx, TOPDECKH);

  // draw inventory icon
  // TODO: hover/open state?
  DrawFrame(window.inv_icon, INVICON.x, INVICON.y);

  for (let act of ACTIONS) {
    // XXX conditions for highlighting? are they always clickable?
    let canhighlight = sentence == null;
    let f = (canhighlight && InRect(mousex, mousey, act)) ?
	hispacefont : spacefont;
    f.Draw(ctx, act.x, act.y, act.text);
  }
    
  // font.Draw(ctx, 1, 1, "USE ID WITH CARD READER");
  DrawSentence(sentence);

  // Objects need to be clipped by the top deck, so only
  // draw lower deck items first...
  DrawItemsWhen((item) => item.worldy > TOPDECKH);
  DrawEntsWhen((ent) => ent.worldy > TOPDECKH);

  DrawFrame(window.topdeckbg, -scrollx, 0);
  
  DrawItemsWhen((item) => item.worldy <= TOPDECKH);
  DrawEntsWhen((ent) => ent.worldy <= TOPDECKH);
  
  if (window.inventoryopen) {
    // Above everything: Inventory
    DrawFrame(window.inventory, INVX, INVY);
    for (let y = 0; y < INVH; y++) {
      for (let x = 0; x < INVW; x++) {
	if (InvUsed(x, y) != null) {
	  DrawFrame(invused, 
		    INVCONTENTSX + INVITEMSIZE * x,
		    INVCONTENTSY + INVITEMSIZE * y);
	}
      }
    }

    for (let o in items) {
      let item = items[o];
      if (item.invx != null) {
	DrawFrame(item.invframes,
		  INVCONTENTSX + INVITEMSIZE * item.invx,
		  INVCONTENTSY + INVITEMSIZE * item.invy);
      }
    }

    // TODO: could highlight filled inventory slots.

    spacefont.Draw(ctx, INVTITLEX, INVTITLEY, "INVENTORY");
  }
    
  // Unmute button?
  
}

function DrawTitle() {
  DrawFrame(window.titleframes, 0, 0);
  spacefont.Draw(ctx, WIDTH * 0.35, HEIGHT * 0.5,
		 "SPACE GAME TITLE TBD");
}

function Draw() {
  switch (window.phase) {
    case PHASE_TITLE:
    DrawTitle();
    break;
    // case PHASE_CUTSCENE:
    // DrawCutscene();
    break;
    case PHASE_GAME:
    DrawGame();
    break;
  }
}

let last = 0;
function Step(time) {
  // Throttle to 30 fps or something we
  // should be able to hit on most platforms.
  // Word has it that 'time' may not be supported on Safari, so
  // compute our own.
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
    
  UpdateStars();
  
  for (var o in ents) {
    let ent = ents[o];
    if (ent.targetx != null) {
      const dx = ent.targetx - ent.worldx
      const dy = ent.targety - ent.worldy;
      // At target?
      if (Math.abs(dx) <= ent.xspeed &&
	  Math.abs(dy) <= ent.yspeed) {
	ent.worldx = ent.targetx;
	ent.worldy = ent.targety;
	ent.targetx = null;
	ent.targety = null;
	continue;
      }

      // XXX use bresenham
      // XXX avoid obstacles if non-convex?
      if (Math.abs(dx) <= ent.xspeed) {
	ent.worldx = ent.targetx;
      } else {
	ent.worldx += dx < 0 ? -ent.xspeed : ent.xspeed;
	if (dx < 0) ent.facingleft = true;
	else if (dx > 0) ent.facingleft = false;
      }
      
      if (Math.abs(dy) <= ent.yspeed) {
	ent.worldy = ent.targety;
      } else {
	ent.worldy += dy < 0 ? -ent.yspeed : ent.yspeed;
      }
    }
  }


  // Update here or in Draw?
  if (player.worldx - SCROLLMARGIN < scrollx) {
    let target = player.worldx - SCROLLMARGIN;
    scrollx = Math.round(((scrollx * 7) + target) * 0.125);
    // scrollx--;
  } else if (player.worldx + SCROLLMARGIN > scrollx + WIDTH) {
    let target = player.worldx + SCROLLMARGIN - WIDTH;
    // scrollx++;
    scrollx = Math.round(((scrollx * 7) + target) * 0.125);
  }
  
  UpdateSong();

  Draw();

  // process music in any state
  // UpdateSong();

  // On every frame, flip to 4x canvas
  bigcanvas.Draw4x(ctx);

  if (DEBUG) {
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
  InitGame();
  InitStars();
  
  // window.phase = PHASE_TITLE;
  // StartSong(song_theme_maj);

  // straight to game to start
  window.phase = PHASE_GAME;

  // For mouse control.
  bigcanvas.canvas.onmousemove = CanvasMove;
  bigcanvas.canvas.onmousedown = CanvasMousedown;
  bigcanvas.canvas.onmouseup = CanvasMouseup;
  
  start_time = (new Date()).getTime();
  window.requestAnimationFrame(Step);
}

function InRect(x, y, r) {
  return x >= r.x && x < r.x + r.w &&
      y >= r.y && y < r.y + r.h;
}

function InCoords(x, y, x0, y0, w, h) {
  return x >= x0 && x < x0 + w &&
      y >= y0 && y < y0 + h;
}

function CanvasMousedownGame(x, y) {
  let globalx = scrollx + x;
  console.log('click ', x, y, " = global ", globalx, y);

  // If we have no sentence, we can always pick a verb
  // (XXX: NOT if we've grabbed an item and need to put it in
  // inventory, though)
  if (sentence == null && y > ACTY) {
    for (let act of ACTIONS) {
      if (InRect(mousex, mousey, act)) {
	console.log('start sentence ', VerbString(act.verb));
	sentence = { verb: act.verb, obj1: null, obj2: null };
	return;
      }
    }
  }

  if (window.inventoryopen) {
    // TODO: First check action clicks, since these are the
    // only thing outside the inventory itself that don't close it
    
    if (InRect(x, y, INVCLOSE) ||
	!InRect(x, y, INVRECT)) {
      window.inventoryopen = false;
    }

    // TODO:
    // click ITEM to snag it
    // (nice to have) drag item?
    // click USE, then ITEM
    // click to close inventory
    
  } else {
    // inventory closed:

    if (InRect(x, y, INVICON)) {
      inventoryopen = true;
      return;
    }

    // In an item?
    for (let o in items) {
      let item = items[o];
      if (item.worldx != null &&
	  InCoords(globalx, y,
		   item.worldx, item.worldy,
		   item.worldw, item.worldh)) {
	// see if we can add to sentence
	sentence = ExtendSentence(item);
      }
    }
	 
    // XXX test that it's in bounds, not item, etc.
    // (double-click to walk?!)
    player.targetx = globalx;
    player.targety = y;
    
    // TODO:
    // click to walk
    // click to form sentence
    // click GET ITEM, open inventory...
  }
}

function CanvasMouseupGame(x, y) {

}

function CanvasMousedown(event) {
  event = event || window.event;
  var bcx = bigcanvas.canvas.offsetLeft;
  var bcy = bigcanvas.canvas.offsetTop;
  var x = Math.floor((event.pageX - bcx) / PX);
  var y = Math.floor((event.pageY - bcy) / PX);

  switch (window.phase) {
    case PHASE_GAME:
    return CanvasMousedownGame(x, y);
    break;
    case PHASE_TITLE:
    ClearSong();
    window.phase = PHASE_GAME;
    break;
  }
}

function CanvasMouseup(event) {
  event = event || window.event;
  var bcx = bigcanvas.canvas.offsetLeft;
  var bcy = bigcanvas.canvas.offsetTop;
  var x = Math.floor((event.pageX - bcx) / PX);
  var y = Math.floor((event.pageY - bcy) / PX);

  switch (window.phase) {
    case PHASE_GAME:
    return CanvasMouseupGame(x, y);
    break;
    case PHASE_TITLE:
    // ignored
    break;
  }
}

function CanvasMove(event) {
  event = event || window.event;
  var bcx = bigcanvas.canvas.offsetLeft;
  var bcy = bigcanvas.canvas.offsetTop;
  var x = Math.floor((event.pageX - bcx) / PX);
  var y = Math.floor((event.pageY - bcy) / PX);
  mousex = x;
  mousey = y;

  // If we use movement anywhere else (unlikely!) then
  // do the switch thing.
  if (window.phase != PHASE_GAME) return;

  // If dragging, etc.
}

// XXX remove "cheat" keys
document.onkeydown = function(event) {
  event = event || window.event;
  if (event.ctrlKey) return true;

  // console.log('key: ' + event.keyCode);

  const kc = event.keyCode;
  switch (kc) {
  case 32:  // SPACE
    if (window.phase == PHASE_TITLE) {
      ClearSong();
      window.phase = PHASE_GAME;
    } else if (window.phase == PHASE_GAME) {
      window.inventoryopen = ! window.inventoryopen;
    }
    break;
  case 38:  // UP
  case 40:  // DOWN
  case 90:  // z
  case 88:  // x
    break;
    
  case 49: 
  case 50:
  case 51:
  case 52:
  case 53:
  case 54:
    player.worldx = WIDTH * (kc - 49 + 0.5); break;
    /*
  case 55: window.phase = PHASE_PUZZLE; Level7(); break;
    case 9:
    if (window.cutscene) {
      var cuts = window.cutscenes[window.cutscene];
      if (cuts) {
	window.cutscene = null;
	cuts.cont();
      }
    }
    break;
    */
    case 27: // ESC
    if (true || DEBUG) {
      ClearSong();
      document.body.innerHTML =
	  '<b style="color:#fff;font-size:40px">(SILENCED. ' +
          'RELOAD TO PLAY)</b>';
      Step = function() { };
      // n.b. javascript keeps running...
    }
    break;
  }
};

resources.WhenReady(Start);