/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "../policy.h"
#include "../backend.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    struct ce_policy p;int fan;struct ce_limits limits={1000,6000};
    assert(!ce_parse("SET 1 manual 2500",&fan,&p)&&fan==1&&p.mode==CE_MANUAL);
    assert(ce_target(&p,limits,NAN,0,0)==2500);
    assert(ce_parse("SET -1 auto",&fan,&p));assert(ce_parse("SET 16 auto",&fan,&p));
    assert(ce_parse("SET 0 manual 2500junk",&fan,&p));assert(ce_parse("SET 0 manual 9999999999999999999",&fan,&p));
    assert(ce_parse("SET 0 auto extra",&fan,&p));assert(ce_parse("SET 0 curve TC0P nan 80",&fan,&p));
    assert(ce_parse("SET 0 curve TC0P 80 80",&fan,&p));assert(ce_parse("SET 0 curve TC0P 50 121",&fan,&p));
    assert(!ce_parse("SET 0 curve TC0P 50 80",&fan,&p));
    assert(ce_target(&p,limits,50,0,2)==1000);
    assert(ce_target(&p,limits,65,0,2)==3500);
    assert(ce_target(&p,limits,80,0,2)==6000);
    assert(ce_target(&p,limits,NAN,1500,2)==6000);
    assert(ce_target(&p,limits,-30,1500,2)==6000);
    assert(ce_target(&p,limits,50,5000,2)==4800);
    assert(ce_target(&p,limits,50,5000,-1)==5000);
    assert(ce_target(&p,limits,80,1000,0)==6000);
    assert(!ce_parse("SET 0 manual 999",&fan,&p));assert(ce_target(&p,limits,NAN,0,0)==-1);
    assert(!ce_parse("SET 0 maximum",&fan,&p));assert(ce_target(&p,limits,NAN,0,0)==6000);
    assert(!ce_parse("SET 0 auto",&fan,&p));assert(ce_target(&p,limits,NAN,0,0)==0);
    assert(ce_force_bit(0x8002,0,1)==0x8003);assert(ce_force_bit(0x8003,0,0)==0x8002);
    assert(ce_force_bit(0x8003,16,0)==0x8003);
    struct ce_value v={.type="sp78",.size=2,.bytes={0xff,0x80}};
    assert(ce_decode(&v)==-0.5);strcpy(v.type,"fpe2");v.bytes[0]=0x21;v.bytes[1]=0x74;
    assert(ce_decode(&v)==2141);v.size=32;assert(isnan(ce_decode(&v)));
    puts("Policy, parser, bitmask and numeric-decoding assertions passed");
}
