const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const source = fs.readFileSync(require.resolve('../../shell/plugins/pawberry/PracticeBridge.qml'), 'utf8')

// Execute the bridge's actual JavaScript methods with a process fixture.
function bridge() {
  const replies = [], jobs = []
  const context = {ready: true, managed: true, current: null, optional: false,
    clientPath: '/installed parent client', watchdog: {start() {}, stop() {}},
    reply(token, result) { replies.push({token, result}) },
    requestProcess: {createObject(parent, properties) {
      const job = {...properties, destroy() { this.destroyed = true }}
      jobs.push(job); return job
    }}}
  context.root = context
  vm.createContext(context)
  const methods = source.slice(source.indexOf('  function cancel()'), source.indexOf('  Timer {'))
  vm.runInContext(methods, context)
  return {context, replies, jobs}
}

test('parent saves send a masked-input password only on stdin, with compatible limit flags', () => {
  for (const [limits, values] of [[{add:5,subtract:10},['5','10']], [{add:null,subtract:0},['unlimited','0']]]) {
    const {context, jobs} = bridge()
    const secret = 'test pa\'ss"$word; $(never-run)'
    context.saveLimits(17, limits, secret)
    assert.equal(jobs.length,1)
    const job = jobs[0]
    assert.deepEqual(Array.from(job.command), ['/installed parent client','limits','--password-stdin','--addition',values[0],'--subtraction',values[1]])
    assert(!job.command.some(arg => arg.includes(secret)))
    assert.equal(job.sendPassword,true)
    const writes = []
    const process = {pendingPassword:job.pendingPassword,sendPassword:job.sendPassword,launched:false,write(value){ writes.push(value) }}
    vm.createContext(process)
    vm.runInContext(source.match(/^      onStarted: \{([\s\S]*?)^      }/m)[1], process)
    assert.deepEqual(writes,[secret+'\n'])
    assert.equal(process.pendingPassword,'')
  }
})

test('unavailable controls cannot report a saved limit and cancellation clears queued credentials', () => {
  for (const property of ['ready','managed']) {
    const {context,jobs,replies} = bridge()
    context[property]=false
    context.saveLimits(1,{add:0,subtract:0},'private')
    assert.equal(jobs.length,0)
    assert.equal(replies[0].result.ok,false)
  }
  const {context,jobs}=bridge()
  context.saveLimits(1,{add:3,subtract:null},'private')
  context.cancel()
  assert.equal(context.current,null)
  assert.equal(jobs[0].pendingPassword,'')
  assert.equal(jobs[0].destroyed,true)
})

test('optional time rewards use one authenticated settings update with no credential arguments', () => {
  const {context,jobs}=bridge()
  context.saveLimits(3,{add:5,subtract:null},'private',{enabled:true,minutes_per_problem:2,daily_cap_minutes:30})
  assert.deepEqual(Array.from(jobs[0].command), ['/installed parent client','settings','--password-stdin',
    '--addition','5','--subtraction','unlimited','--screen-time','on','--minutes-per-problem','2','--daily-reward-minutes','30'])
  assert.equal(jobs[0].pendingPassword,'private')
  assert.equal(jobs[0].sendPassword,true)
})

test('background status checks yield to a parent save and cannot interrupt its password check', () => {
  const {context,jobs}=bridge()
  context.request(-1,{cmd:'status'})
  context.saveLimits(9,{add:5,subtract:5},'private')
  assert.equal(jobs.length,2)
  assert.equal(jobs[0].destroyed,true)
  context.refresh()
  assert.equal(jobs.length,2)
  assert.equal(context.current.token,9)
})
