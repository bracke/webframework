with Web.Binding.Paths;
with Web.Binding.Results;

--  Defensive decode boundary.
--
--  Wraps a decoder so that any exception it raises -- a violated internal
--  invariant, a programmer error in an application-authored decoder, an
--  unexpected runtime failure -- is caught and converted to a deterministic
--  internal.decoder_failure result rather than propagating. The converted error
--  carries only the path and id, never request data, so nothing sensitive leaks
--  through the boundary. Ordinary malformed input is still returned as a
--  structured result by the wrapped decoder; this only backstops the unexpected.
generic
   type Target is private;
   with package Field_Results is new Web.Binding.Results (Target);
   with function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Field_Results.Result;
function Web.Binding.Decoders.Guard
  (Text   : String;
   Path   : Web.Binding.Paths.Field_Path;
   Source : Source_Kind) return Field_Results.Result;
