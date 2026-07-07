--  Compatibility wrapper for action dispatch.
with App.Runtime;

--  This package is now a rename to the convenience façade nested dispatcher.
package App.Dispatcher renames App.Runtime.Dispatcher;
