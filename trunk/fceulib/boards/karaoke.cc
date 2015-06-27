/* FCE Ultra - NES/Famicom Emulator
 *
 * Copyright notice for this file:
 *  Copyright (C) 2002 Xodnizel
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include "mapinc.h"

#include "ines.h"

static uint8 latche;

static void Sync(void) {
  if(latche) {
    if(latche&0x10)
      fceulib__cart.setprg16(0x8000,(latche&7));
    else
      fceulib__cart.setprg16(0x8000,(latche&7)|8);
  } else {
    fceulib__cart.setprg16(0x8000,7+(fceulib__ines.ROM_size>>4));
  }
}

static DECLFW(M188Write) {
  latche=V;
  Sync();
}

static DECLFR(ExtDev) {
  return 3;
}

static void Power(void) {
  latche=0;
  Sync();
  fceulib__cart.setchr8(0);
  fceulib__cart.setprg16(0xc000,0x7);
  fceulib__fceu.SetReadHandler(0x6000,0x7FFF,ExtDev);
  fceulib__fceu.SetReadHandler(0x8000,0xFFFF,Cart::CartBR);
  fceulib__fceu.SetWriteHandler(0x8000,0xFFFF,M188Write);
}

static void StateRestore(int version) {
  Sync();
}

void Mapper188_Init(CartInfo *info) {
  info->Power=Power;
  fceulib__fceu.GameStateRestore=StateRestore;
  AddExState(&latche, 1, 0, "LATC");
}
