ARGIND <= 5 {
  line = $0
  while (match(line, /(^## |\*\*|\| )((C|FR|NFR|D|Q|F)-[0-9]+)(:\*\*|\*\*| —| \|)/, fields)) {
    defined[fields[2]] = 1
    line = substr(line, RSTART + RLENGTH)
  }
  next
}
{
  line = $0
  while (match(line, /\<(C|FR|NFR|D|Q|F)-[0-9]+\>/)) {
    id = substr(line, RSTART, RLENGTH)
    if (!(id in defined)) {
      print FILENAME ":" FNR ": unknown product ID " id > "/dev/stderr"
      failed = 1
    }
    line = substr(line, RSTART + RLENGTH)
  }
}
END { exit failed }
