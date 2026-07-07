--  Application-level convenience façade.
--
--  `App.Runtime` is the main entry point for dispatcher and live wiring.
with App.State;
with Web.Application;

package App.Runtime is new Web.Application
  (App_State     => App.State.App_State,
   Initial_State => App.State.Initial_State);
