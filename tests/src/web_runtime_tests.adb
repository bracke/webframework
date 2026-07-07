with Ada.Text_IO;
with AUnit.Assertions;
with AUnit.Test_Caller;
with GNAT.OS_Lib;

package body Web_Runtime_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use type GNAT.OS_Lib.String_Access;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("browser runtime behavior", Test_Runtime_Behavior'Access));
   end Add_Tests;

   procedure Put (File : in out Ada.Text_IO.File_Type; Line : String) is
   begin
      Ada.Text_IO.Put_Line (File, Line);
   end Put;

   procedure Write_Harness (Path : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Put (File, "const fs = require('fs');");
      Put (File, "const vm = require('vm');");
      Put (File, "const sent = [];");
      Put (File, "function assert(c, m) { if (!c) { throw new Error(m); } }");
      Put (File, "class FakeWebSocket {");
      Put (File, "  constructor(url) {");
      Put (File, "    this.url = url; this.readyState = 1; this.listeners = {};");
      Put (File, "    FakeWebSocket.instance = this;");
      Put (File, "  }");
      Put (File, "  addEventListener(n, cb) { (this.listeners[n] ||= []).push(cb); }");
      Put (File, "  send(m) { sent.push(m); }");
      Put (File, "  emit(n, e) { (this.listeners[n] || []).forEach(cb => cb(e)); }");
      Put (File, "}");
      Put (File, "FakeWebSocket.OPEN = 1;");
      Put (File, "FakeWebSocket.CONNECTING = 0;");
      Put (File, "class ClassList {");
      Put (File, "  constructor() { this.values = new Set(); }");
      Put (File, "  add(v) { this.values.add(v); }");
      Put (File, "  remove(v) { this.values.delete(v); }");
      Put (File, "  contains(v) { return this.values.has(v); }");
      Put (File, "}");
      Put (File, "class Element {");
      Put (File, "  constructor(id, tag = 'div') {");
      Put (File, "    this.id = id; this.tagName = tag.toUpperCase(); this.attrs = {}; this.children = [];");
      Put (File, "    this.parent = null; this.classList = new ClassList();");
      Put (File, "    this.innerHTML = ''; this.textContent = '';");
      Put (File, "    this.value = ''; this.fields = {};");
      Put (File, "  }");
      Put (File, "  appendChild(c) { c.parent = this; this.children.push(c); }");
      Put (File, "  contains(e) { for (let n = e; n; n = n.parent) { if (n === this) return true; } return false; }");
      Put (File, "  setAttribute(n, v) { this.attrs[n] = String(v); }");
      Put (File, "  getAttribute(n) { return this.attrs[n] || null; }");
      Put (File, "  removeAttribute(n) { delete this.attrs[n]; }");
      Put (File, "  focus() { document.activeElement = this; }");
      Put (File, "  closest(sel) {");
      Put (File, "    for (let n = this; n; n = n.parent) {");
      Put (File, "      if (sel === '[data-wf-click]' && n.attrs['data-wf-click']) return n;");
      Put (File, "      if (sel === 'form[data-wf-submit]' && n.tagName === 'FORM'");
      Put (File, "          && n.attrs['data-wf-submit']) return n;");
      Put (File, "    }");
      Put (File, "    return null;");
      Put (File, "  }");
      Put (File, "}");
      Put (File, "const document = {");
      Put (File, "  elements: {}, listeners: {}, activeElement: null, readyState: 'loading',");
      Put (File, "  body: new Element('body', 'body'),");
      Put (File, "  getElementById(id) { return this.elements[id] || null; },");
      Put (File, "  addEventListener(n, cb) { (this.listeners[n] ||= []).push(cb); },");
      Put (File, "  dispatchEvent(e) { (this.listeners[e.type] || []).forEach(cb => cb(e)); }");
      Put (File, "};");
      Put (File, "document.body.setAttribute('data-wf-ws', '/ws');");
      Put (File, "function add(e) { document.elements[e.id] = e; return e; }");
      Put (File, "global.document = document;");
      Put (File, "global.window = { location: { protocol: 'http:', host: 'example.test' } };");
      Put (File, "global.WebSocket = FakeWebSocket;");
      Put (File, "global.FormData = function(form) {");
      Put (File, "  this.forEach = cb => Object.keys(form.fields).forEach(k => cb(form.fields[k], k));");
      Put (File, "};");
      Put (File, "const runtimePath = fs.existsSync('../static/webframework.js')");
      Put (File, "  ? '../static/webframework.js' : 'static/webframework.js';");
      Put (File, "vm.runInThisContext(fs.readFileSync(runtimePath, 'utf8'));");
      Put (File, "document.dispatchEvent({ type: 'DOMContentLoaded' });");
      Put (File, "FakeWebSocket.instance.emit('open', {});");
      Put (File, "assert(JSON.parse(sent[0]).type === 'hello', 'hello sent');");
      Put (File, "const target = add(new Element('target'));");
      Put (File, "const input = add(new Element('child', 'input'));");
      Put (File, "target.appendChild(input);");
      Put (File, "target.innerHTML = '<input id=""child"">'; input.focus();");
      Put (File, "window.WebFramework.applyPatches([{ op: 'replace_html', target: 'target', value: '<b>new</b>' }]);");
      Put (File, "assert(target.innerHTML === '<input id=""child"">', 'focused replace blocked');");
      Put (File, "window.WebFramework.applyPatches([{");
      Put (File, "  op: 'replace_html', target: 'target', value: '<b>new</b>', force: true");
      Put (File, "}]);");
      Put (File, "assert(target.innerHTML === '<b>new</b>', 'forced replace applied');");
      Put (File, "window.WebFramework.applyPatches([{ op: 'set_text', target: 'target', value: 'plain' }]);");
      Put (File, "assert(target.textContent === 'plain', 'set_text applied');");
      Put (File, "window.WebFramework.applyPatches([{");
      Put (File, "  op: 'set_attr', target: 'target', name: 'aria-live', value: 'polite'");
      Put (File, "}]);");
      Put (File, "assert(target.getAttribute('aria-live') === 'polite', 'set_attr applied');");
      Put (File, "window.WebFramework.applyPatches([{ op: 'remove_attr', target: 'target', name: 'aria-live' }]);");
      Put (File, "assert(target.getAttribute('aria-live') === null, 'remove_attr applied');");
      Put (File, "window.WebFramework.applyPatches([{ op: 'add_class', target: 'target', name: 'active' }]);");
      Put (File, "assert(target.classList.contains('active'), 'add_class applied');");
      Put (File, "window.WebFramework.applyPatches([{ op: 'remove_class', target: 'target', name: 'active' }]);");
      Put (File, "assert(!target.classList.contains('active'), 'remove_class applied');");
      Put (File, "window.WebFramework.applyPatches([{ op: 'set_value', target: 'child', value: 'Bent' }]);");
      Put (File, "assert(input.value === 'Bent', 'set_value applied');");
      Put (File, "FakeWebSocket.instance.emit('message', { data: JSON.stringify({");
      Put (File, "  type: 'patches',");
      Put (File, "  patches: [{ op: 'set_text', target: 'target', value: 'from socket' }]");
      Put (File, "}) });");
      Put (File, "assert(target.textContent === 'from socket', 'socket patch applied');");
      Put (File, "FakeWebSocket.instance.emit('message', { data: 'not-json' });");
      Put (File, "FakeWebSocket.instance.emit('message', { data: JSON.stringify({");
      Put (File, "  type: 'patches', patches: {}");
      Put (File, "}) });");
      Put (File, "assert(target.textContent === 'from socket', 'bad socket messages ignored');");
      Put (File, "const button = add(new Element('counter-inc', 'button'));");
      Put (File, "button.setAttribute('data-wf-click', 'counter.increment');");
      Put (File, "document.dispatchEvent({ type: 'click', target: button });");
      Put (File, "let click = JSON.parse(sent[sent.length - 1]);");
      Put (File, "assert(click.type === 'click' && click.id === 'counter-inc'");
      Put (File, "  && click.action === 'counter.increment' && click.version === 1, 'click sent');");
      Put (File, "const form = add(new Element('profile-form', 'form'));");
      Put (File, "form.setAttribute('data-wf-submit', 'profile.save');");
      Put (File, "form.fields = { name: 'Bent' };");
      Put (File, "let prevented = false;");
      Put (File, "document.dispatchEvent({ type: 'submit', target: form, preventDefault() { prevented = true; } });");
      Put (File, "let submit = JSON.parse(sent[sent.length - 1]);");
      Put (File, "assert(prevented, 'submit prevented');");
      Put (File, "assert(submit.type === 'submit' && submit.id === 'profile-form'");
      Put (File, "  && submit.action === 'profile.save', 'submit sent');");
      Put (File, "assert(submit.fields.name === 'Bent' && submit.version === 1, 'submit fields sent');");
      Put (File, "const todoForm = add(new Element('todo-form', 'form'));");
      Put (File, "const title = add(new Element('title', 'input'));");
      Put (File, "const todoStatus = add(new Element('todo-status'));");
      Put (File, "const todoList = add(new Element('todo-list', 'ul'));");
      Put (File, "todoForm.setAttribute('data-wf-submit', 'todo.add');");
      Put (File, "todoForm.fields = { title: 'Ship release' };");
      Put (File, "document.dispatchEvent({ type: 'submit', target: todoForm, preventDefault() {} });");
      Put (File, "let todoSubmit = JSON.parse(sent[sent.length - 1]);");
      Put (File, "assert(todoSubmit.type === 'submit' && todoSubmit.action === 'todo.add', 'todo submit sent');");
      Put (File, "assert(todoSubmit.fields.title === 'Ship release', 'todo title sent');");
      Put (File, "window.WebFramework.applyPatches([");
      Put (File, "  { op: 'replace_html', target: 'todo-list', value: '<li>Ship release</li>' },");
      Put (File, "  { op: 'set_text', target: 'todo-status', value: 'Added Ship release' },");
      Put (File, "  { op: 'set_value', target: 'title', value: '' }");
      Put (File, "]);");
      Put (File, "assert(todoList.innerHTML === '<li>Ship release</li>', 'example todo list patched');");
      Put (File, "assert(todoStatus.textContent === 'Added Ship release', 'example todo status patched');");
      Put (File, "assert(title.value === '', 'example todo input cleared');");
      Put (File, "console.log('PASS runtime behavior');");
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Harness;

   procedure Test_Runtime_Behavior (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Node_Path : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("node");
      Success   : Boolean;
      Harness   : constant String := "/tmp/webframework_runtime_test.js";
   begin
      Assert (Node_Path /= null, "node executable is required for runtime tests");
      Write_Harness (Harness);
      declare
         Args : GNAT.OS_Lib.Argument_List :=
           (1 => new String'(Harness));
      begin
         GNAT.OS_Lib.Spawn (Node_Path.all, Args, Success);
         GNAT.OS_Lib.Free (Args (1));
      end;
      GNAT.OS_Lib.Free (Node_Path);
      Assert (Success, "runtime harness failed");
   end Test_Runtime_Behavior;
end Web_Runtime_Tests;
