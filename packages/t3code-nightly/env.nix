{
  formats,
  t3code-meta,
}:

let
  kv = formats.keyValue { };
in

kv.generate "${t3code-meta.pname}-env" { }
