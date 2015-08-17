/* FCE Ultra - NES/Famicom Emulator
 *
 * Copyright notice for this file:
 *  Copyright (C) 2005 CaH4e3
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
 *
 * Lethal Weapon (VRC4 mapper)
 */

#include "mapinc.h"

static uint8 prg0, prg1, mirr, tfswap;
static uint8 chr[8];
static uint8 IRQCount;
static uint8 IRQPre;
static uint8 IRQa;

static vector<SFORMAT> StateRegs = {
    {&prg0, 1, "PRG0"},   {&prg0, 1, "PRG1"}, {&mirr, 1, "MIRR"},
    {&tfswap, 1, "SWAP"},   {chr, 8, "CHR0"},    {&IRQCount, 1, "IRQC"},
    {&IRQPre, 1, "IRQP"}, {&IRQa, 1, "IRQA"}};

static void SyncPrg() {
  if (tfswap & 3) {
    fceulib__.cart->setprg8(0x8000, ~1);
    fceulib__.cart->setprg8(0xC000, prg0);
  } else {
    fceulib__.cart->setprg8(0x8000, prg0);
    fceulib__.cart->setprg8(0xC000, ~1);
  }
  fceulib__.cart->setprg8(0xA000, prg1);
  fceulib__.cart->setprg8(0xE000, ~0);
}

static void SyncChr() {
  for (int i = 0; i < 8; i++) fceulib__.cart->setchr1(i << 10, chr[i]);
  fceulib__.cart->setmirror(mirr ^ 1);
}

static void StateRestore(FC *fc, int version) {
  SyncPrg();
  SyncChr();
}

static DECLFW(UNLTF1201Write) {
  A = (A & 0xF003) | ((A & 0xC) >> 2);
  if ((A >= 0xB000) && (A <= 0xE003)) {
    int ind = (((A >> 11) - 6) | (A & 1)) & 7;
    int sar = ((A & 2) << 1);
    chr[ind] = (chr[ind] & (0xF0 >> sar)) | ((V & 0x0F) << sar);
    SyncChr();
  } else {
    switch (A & 0xF003) {
      case 0x8000:
        prg0 = V;
        SyncPrg();
        break;
      case 0xA000:
        prg1 = V;
        SyncPrg();
        break;
      case 0x9000:
        mirr = V & 1;
        SyncChr();
        break;
      case 0x9001:
        tfswap = V & 3;
        SyncPrg();
        break;
      case 0xF000: IRQCount = ((IRQCount & 0xF0) | (V & 0xF)); break;
      case 0xF002: IRQCount = ((IRQCount & 0x0F) | ((V & 0xF) << 4)); break;
      case 0xF001:
      case 0xF003:
        IRQa = V & 2;
        fceulib__.X->IRQEnd(FCEU_IQEXT);
        if (fceulib__.ppu->scanline < 240) IRQCount -= 8;
        break;
    }
  }
}

static void UNLTF1201IRQCounter() {
  if (IRQa) {
    IRQCount++;
    if (IRQCount == 237) {
      fceulib__.X->IRQBegin(FCEU_IQEXT);
    }
  }
}

static void UNLTF1201Power(FC *fc) {
  IRQPre = IRQCount = IRQa = 0;
  fceulib__.fceu->SetReadHandler(0x8000, 0xFFFF, Cart::CartBR);
  fceulib__.fceu->SetWriteHandler(0x8000, 0xFFFF, UNLTF1201Write);
  SyncPrg();
  SyncChr();
}

void UNLTF1201_Init(CartInfo *info) {
  info->Power = UNLTF1201Power;
  fceulib__.ppu->GameHBIRQHook = UNLTF1201IRQCounter;
  fceulib__.fceu->GameStateRestore = StateRestore;
  fceulib__.state->AddExVec(StateRegs);
}