--  Request-body ownership.
--
--  A request body has one explicit owner and its consumption state is tracked
--  (BIND-001). A codec claims the body before decoding; a second claim after it
--  has been consumed (or while it is being decoded) is refused, so the caller
--  can report binding.source_already_consumed instead of double-reading a stream.
package Web.Binding.Bodies is

   type Body_State is (Available, Decoding, Consumed, Failed);

   type Body_Claim is limited private;

   --  A fresh, available body claim.
   --  @return The claim.
   function New_Body return Body_Claim;

   --  The current state.
   --  @param Item The claim.
   --  @return Its state.
   function State (Item : Body_Claim) return Body_State;

   --  Attempt to claim the body for decoding. Succeeds only when Available.
   --  @param Item The claim.
   --  @param Ok True if the claim was granted.
   procedure Claim (Item : in out Body_Claim; Ok : out Boolean);

   --  Release the claim after decoding, marking it Consumed or Failed.
   --  @param Item The claim.
   --  @param Success Whether decoding succeeded.
   procedure Release (Item : in out Body_Claim; Success : Boolean);

private

   type Body_Claim is limited record
      Current : Body_State := Available;
   end record;

end Web.Binding.Bodies;
