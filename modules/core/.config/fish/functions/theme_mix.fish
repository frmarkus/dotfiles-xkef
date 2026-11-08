function theme_mix -a base color weight -d "Mix two rrggbb colors, weight 0 for base to 1 for color"
    for i in 1 3 5
        set -l b 0x(string sub -s $i -l 2 $base)
        set -l c 0x(string sub -s $i -l 2 $color)
        printf '%02x' (math "round($b + ($c - $b) * $weight)")
    end
end
