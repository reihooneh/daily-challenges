# Farswell

**Reads a swell backwards: from the periods your buoys report, it works out when and where the distant storm blew, then tells you when each period reaches your beach.**

Long-period swell outruns short-period swell. A storm thousands of kilometres away makes every period at once, but the 20-second waves arrive first and the 12-second ones a day or two later. Plot frequency (1 / period) against arrival time and one storm draws a straight line: the slope gives its distance and the line's crossing of the time axis gives when it blew. Farswell fits those lines robustly at every buoy, makes all buoys agree on one storm time, and finds the point on the globe that sits at the right distance from each of them.

## Features

- **Robust fit at each buoy.** Theil-Sen regression (median of pairwise slopes), so a local wind sea or a second swell mixed into the readings is flagged as an outlier instead of dragging the line.
- **One storm time for all buoys.** A joint fit shares the start time across buoys and gives each its own distance; a one-number search plus golden-section refinement.
- **Locates the storm on a sphere.** Great-circle trilateration from the distances, nudged by the swell direction where the buoy reports one. If two places fit (a mirror image across a line of buoys) it says so rather than picking one quietly.
- **Honest error bars.** A seeded residual bootstrap refits everything, giving a 90% range for the storm time, each distance, the storm's position, and each arrival at your beach.
- **Forecast for any beach.** `--beach NAME:LAT:LON` lists when 22 s to 10 s swell arrives, in your time zone (`--tz`).
- **Text output in four shapes:** a frequency-time chart, a buoy table, a map of buoys, swell paths and storm, and a forecast table.
- Pure core Perl 5 - no CPAN modules to install.

## Example

`examples/southern-ocean.txt` holds three NSW buoys watching a Southern Ocean swell (made from a storm at 52° S 162° E on 17 Nov 18:00 UTC, rounded to 0.1 s with noise, and with six hours of local wind sea at Sydney). Farswell isn't told any of that:

```
$ bin/farswell --beach Newcastle:-32.93:151.78 --tz 11 examples/southern-ocean.txt

FARSWELL - where the swell came from

Frequency against time. Each swell from one storm is a straight line;
the steeper the line, the closer the storm.

  mHz  period
124.7   8.0s |                                                            
             |                      x   x                            .....
             |                                                  .....     
105.7   9.5s |                                             .....         .
             |                                        .....        ...... 
             |                                  ......       ......       
 86.6  11.5s |                             .E...      .S.....          ..B
             |                        ..E..     ...S..          ..B..B.   
             |                  E...E.    ..S..S         .B...B.          
 67.6  14.8s |             ..E..    ......       ..B...B.                 
             |       E...E.   ..S...      ..B..B.                         
             |   .E...  .S...S    ..B...B.                                
 48.5  20.6s |E......S..   ..B..B.                                        
             |...  ........                                               
             +------------------------------------------------------------
              0 h                         24 h                        48 h   after Thu 19 Nov 14:00 UTC+11
              B Byron  S Sydney  E Eden   x outlier   . fitted line


BUOYS
  buoy         readings outliers  storm distance         90% range
  Byron              13        0    2684 km (  60 h at 16 s)  2649 -  2713 km
  Sydney             10        2    2216 km (  49 h at 16 s)  2187 -  2247 km
  Eden                9        0    1904 km (  42 h at 16 s)  1873 -  1937 km

STORM  made this swell at Wed 18 Nov 04:38 UTC+11
       90% range Wed 18 Nov 03:53 UTC+11  to  Wed 18 Nov 05:24 UTC+11
       near 52.1S 162.3E, within 33 km in 9 of 10 refits

MAP
  20.0S |+                    +                    +                    +|
        |                                                                |
        |                                                                |
        |                                                                |
        |                                                                |
        |+                    +       B.           +                    +|
        |                              ..                                |
        |                        S@.    ..                               |
        |                         ....   ..                              |
        |                     E.   ....   ..                             |
        |+                    + ...  ....   ..     +                    +|
  41.0S |+                    +   .... ....  ..    +                    +|
        |                            ...  ... ...                        |
        |                               ....... ..                       |
        |                                  .........                     |
        |                                      .......                   |
        |+                    +                    +....                +|
        |                                              o*o               |
        |                                                                |
        |                                                                |
        |                                                                |
  60.0S |+                    +                    +                    +|
        +----------------------------------------------------------------+
         140E                                                        170E
         * storm   o bootstrap refits   . swell path   @ Newcastle   + 10-degree grid


FORECAST for Newcastle (2296 km from the storm)
  period  arrives                    90% window
    22 s  Thu 19 Nov 17:47 UTC+11    -0.3 h / +0.3 h
    20 s  Thu 19 Nov 21:30 UTC+11    -0.2 h / +0.2 h
    18 s  Fri 20 Nov 02:02 UTC+11    -0.2 h / +0.2 h
    16 s  Fri 20 Nov 07:43 UTC+11    -0.1 h / +0.1 h
    14 s  Fri 20 Nov 15:01 UTC+11    -0.1 h / +0.1 h
    12 s  Sat 21 Nov 00:45 UTC+11    -0.2 h / +0.2 h
    10 s  Sat 21 Nov 14:22 UTC+11    -0.4 h / +0.4 h
  (great-circle path; land in the way is not checked)

Bootstrap: 200 refits. Deep-water swell, spherical Earth, storm treated as one point in space and time.
```

The answer lands within 25 km and 25 minutes of the real storm, and the two wind-sea readings at Sydney are marked `x` and left out. Remove the directions from the file and Farswell reports a second, mirror-image fit in the Great Australian Bight and warns you to add directions.

## Input

```
# comments start with #
buoy Sydney -33.77 151.42            # name, latitude, longitude
2026-11-20T03:00Z 19.1 165           # UTC time, peak period (s), direction FROM (deg, optional)
2026-11-20T06:00Z 18.2
```

Use the peak period of the one swell you are tracking. Most buoy sites (and their CSV downloads) give peak period and direction every 30-60 minutes.

## Run and test

Needs Perl 5.30 or newer (for `Time::Local::timegm_modern`); nothing else.

```bash
bin/farswell examples/southern-ocean.txt
bin/farswell --beach Bondi:-33.89:151.27 --tz 11 --reps 500 examples/southern-ocean.txt
prove -l t                                    # 145 tests
perlcritic --profile .perlcriticrc bin lib    # clean at "stern" (severity 4)
```

Options: `--beach NAME:LAT:LON`, `--tz HOURS` (-12..14), `--reps N` bootstrap refits (0..1000, default 200), `--seed N`.

## Security

What is protected:

- **Every input is validated and bounded.** Files must be regular files (symlinks, directories, devices and FIFOs are refused) of at most 1 MiB; at most 20,000 lines of 200 characters, 12 buoys and 600 readings per buoy. Latitudes, longitudes, periods (4-30 s), directions and dates (1970-2100, real calendar days, UTC only) are range-checked; numbers must be plain decimals, so `NaN`, `inf` and `1e999` are refused. Buoy and beach names are limited to letters, digits, `_ . -`.
- **Bounded work.** The input caps keep the quadratic Theil-Sen step and the bootstrap (at most 1,000 refits) to a few seconds.
- **No code execution paths.** No string `eval`, no shell, no `system` or backticks in the program, no deserialisation; input is only ever split and matched against anchored patterns.
- **Clean failures.** Errors exit with status 2 and a one-line message, without Perl file paths or line numbers.
- No network access, no secrets, no files written.

Known limits: no software is 100% hack-proof, and this is a hobby tool, not a navigation or safety service. The physics assumes deep water, a point-like storm that made every period at once, and great-circle travel; real storms move and spread over hundreds of kilometres, so the bootstrap error bars are a floor, not a guarantee. Land between the storm and your beach is not checked.
