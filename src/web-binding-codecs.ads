--  Body codecs.
--
--  Parent of the incoming-body codecs (URL-encoded, JSON, multipart). Each
--  consumes a Web.Binding.Streams input stream and produces a source or a typed
--  binding, never reparsing the request. This package is a namespace root.
package Web.Binding.Codecs is

   pragma Pure;

end Web.Binding.Codecs;
