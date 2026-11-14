const { chromium } = require('playwright');
const { pathToFileURL } = require('url');
const path = require('path');
const assert = require('assert/strict');
(async () => {
  const browser=await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  try {
    for (const [name,width,height] of [['pc',1280,720],['portrait',390,844],['landscape',844,390]]) {
      const page=await browser.newPage({viewport:{width,height},hasTouch:name!=='pc'});
      const errors=[]; page.on('pageerror',e=>errors.push(e.message));
      await page.addInitScript(() => { window.requestAnimationFrame=()=>0; localStorage.setItem('minato-gp-v2',JSON.stringify({seenHowto:true,quality:'medium'})); });
      await page.goto(pathToFileURL(path.resolve(__dirname,'../index.html')).href);
      await page.waitForFunction(()=>window.__game,null,{timeout:120000});
      await page.evaluate(()=>{window.__advanceOpening=(seconds)=>{for(let i=0;i<seconds*60 && window.__game.G.state==='opening';i++)window.__game.step(1/60);};});
      await page.click('#btn-start');
      assert.equal(await page.evaluate(()=>window.__game.G.state),'opening');
      await page.evaluate(()=>{const g=window.__game;window.__advanceOpening(2);g.stage.render(null);});
      if(process.env.OUT) await page.screenshot({path:path.join(process.env.OUT,`opening-${name}.png`)});
      const overflow=await page.locator('#opening header, .opening-racer, #opening footer button').evaluateAll(els=>els.some(el=>{const r=el.getBoundingClientRect();return r.left<0||r.right>innerWidth||r.top<0||r.bottom>innerHeight;}));
      assert.equal(overflow,false,'opening text/buttons stay inside viewport');
      assert.equal(await page.locator('#touch').isVisible(),false);
      await page.click('#btn-opening-mute');
      assert.equal(await page.evaluate(()=>window.__game.audio.muted && window.__game.G.state==='opening'),true);
      await page.click('#btn-opening-mute');
      await page.evaluate(()=>{window.__openingMusic=window.__game.audio.openingMusic;});
      if(process.env.OUT) {
        await page.evaluate(()=>{const g=window.__game;window.__advanceOpening(12);g.stage.render(null);});
        await page.screenshot({path:path.join(process.env.OUT,`opening-pit-${name}.png`)});
      }
      const verify=async()=>assert.equal(await page.evaluate(()=>{
        const g=window.__game,r=g.race,expected=new r.constructor(structuredClone(r.cfg));
        return g.G.state==='race' && r.clock===expected.clock && r.stepN===0 && r.rec.length===0 && JSON.stringify(r.boats)===JSON.stringify(expected.boats) && !g.audio.openingMusic;
      }),true,'clock handoff must equal a new Race');
      await page.evaluate(()=>{const g=window.__game;window.__advanceOpening(30.1);}); await verify();
      await page.waitForTimeout(1700);
      assert.equal(await page.evaluate(()=>window.__openingMusic.nodes.size),0,'faded audio nodes released');
      await page.evaluate(()=>window.__game.startRace()); await page.click('#btn-opening-skip'); await verify();
      await page.evaluate(()=>window.__game.startRace()); await page.keyboard.press('Enter'); await verify();
      await page.evaluate(()=>window.__game.startRace()); await page.mouse.click(10,height-100); await verify();
      await page.evaluate(()=>window.__game.toTitle());
      await page.click('#btn-settings'); await page.uncheck('#set-opening');
      assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('minato-gp-v2')).opening),false);
      await page.click('#btn-settings-close'); await page.click('#btn-start'); await verify();
      await page.evaluate(()=>{const g=window.__game;g.S.opening=true;g.S.mode='practice';g.startRace();}); await verify();
      await page.evaluate(()=>{const g=window.__game;g.S.mode='gp';g.G.gp={round:1,pts:{P:0,0:0,1:0,2:0,3:0,4:0},best:{P:9,0:9,1:9,2:9,3:9,4:9},hist:[]};g.startRace();});
      assert.equal(await page.evaluate(()=>window.__game.G.opening.duration),10);
      await page.evaluate(()=>window.__advanceOpening(10.1)); await verify();
      assert.deepEqual(errors,[]);
      console.log(name,'opening, skip, settings, practice, GP and initial state passed');
      await page.close();
    }
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
