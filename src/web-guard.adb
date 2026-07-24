package body Web.Guard is

   function Proceed return Guard_Outcome is
   begin
      return Guard_Outcome'(Decision => Proceed);
   end Proceed;

   function Halt (Response : Web.Response.Response_Type) return Guard_Outcome is
   begin
      return Guard_Outcome'(Decision => Halt, Response => Response);
   end Halt;

end Web.Guard;
