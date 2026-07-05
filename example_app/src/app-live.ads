with App.Dispatcher;
with App.State;
with Web.Live;

package App.Live is new Web.Live
  (App_State     => App.State.App_State,
   Initial_State => App.State.Initial_State,
   Dispatch      => App.Dispatcher.Dispatch);
