#!/bin/sh

#
# global constants
#

# input directory (path) for source images having 
#  - regions defined in the image metadata
#  - default EXIF orientation (value 1 or no tag)
input_dir=input
# output directory (path) for generated images
output_dir=images
# temp directory for intermediate files; they are kept for inspection just in case
tmp_dir=tmp
# image annotation font
font_size=40
# image extension
ext="jpg"
# auxiliary exiftool files from https://github.com/exiftool/exiftool
exiftool_rotate_regions_config="vendor/exiftool/rotate_regions.config"
exiftool_exif2xmp_args="vendor/exiftool/exif2xmp.args"

# orientation options
# https://imagemagick.org/script/command-line-options.php#orient
# top-left        1: Do nothing
# top-right       2: Flip horizontally
# bottom-right    3: Rotate 180 degrees
# bottom-left     4: Flip vertically
# left-top        5: Rotate 90 degrees and flip horizontally (transpose)
# right-top       6: Rotate 90 degrees
# right-bottom    7: Rotate 90 degrees and flip vertically (transverse)
# left-bottom     8: Rotate 270 degrees
IM[3]="bottom-right"
IM[6]="right-top"
IM[8]="left-bottom"
# https://github.com/exiftool/exiftool/blob/master/config_files/rotate_regions.config
ET[3]="RotateMWGRegionCW180"
ET[6]="RotateMWGRegionCW90"
ET[8]="RotateMWGRegionCW270"
# human friendly description
description[3]="rotate 180°"
description[6]="rotate 90°"
description[8]="rotate 270°"
# complement/opposite/inverse of orientation
# used to create an intermediate file representing "original" photo (as shot)
inverse[3]=3
inverse[6]=8
inverse[8]=6

# metadata storage options
STOR_EMBEDDED=embedded                  # image only
STOR_EMBEDDED_SIDECAR=embedded_sidecar  # both image and sidecar
STOR_SIDECAR=sidecar                    # sidecar only

#
# functions
#

log() {
    printf "\n%s\n%s\n" "$@" "----------------------------------------"
}

generate_all_orientations() {
    input_file="$1"
    storage="$2"

    log "Initial metadata (Orientation, RegionInfo) from: $input_file"
    exiftool -struct -j -Orientation -RegionInfo "$input_file"

    log "Generate various 'orientation' x 'metadata storage' combinations for $input_file"

    # target: 3 (bottom-right, Rotate 180 degrees)
    generate 3 "$input_file" "$storage"

    # target: 6 (right-top, Rotate 90 degrees)
    # 6 is typical for vertical/portrait photos on smartphones
    generate 6 "$input_file" "$storage"

    # target: 8 (left-bottom, Rotate 270 degrees)
    # 8 appears in vertical DSLR shots?
    generate 8 "$input_file" "$storage"
}

generate() {
    orientation="$1"
    # input image file (path)
    input_file="$2"
    # metadata storage
    storage="$3"

    inverse_orientation="${inverse[$orientation]}"
    # imagemagick orientation option for an intermediate file (complement/opposite/inverse of orientation)
    inverse_imagemagick="${IM[$inverse_orientation]}"
    # exiftool orientation option for an intermediate file (complement/opposite/inverse of orientation)
    inverse_exiftool="${ET[$inverse_orientation]}"

    filename=$(basename -- "$input_file" ".$ext")

    # intermediate images
    img_annotated="$tmp_dir/$filename.$orientation.$storage.step1.annotated.$ext"
    img_transformed="$tmp_dir/$filename.$orientation.$storage.step2.transformed.$ext"
    img_regions_transformed="$tmp_dir/$filename.$orientation.$storage.step3.regions_transformed.$ext"
    # final image and sidecar files
    img="$output_dir/$filename.$orientation.$storage.$ext"
    sidecar="$img.xmp"

    # image transformation
    log "Generate orientation=$orientation storage=$storage for $input_file"

    log "1. Annotate: $orientation $storage: $input_file -> $img_annotated"
    magick "$input_file" \
        -pointsize $font_size -fill white -stroke black -strokewidth 1 \
        -gravity North -draw 'text 10,10 Top' \
        -gravity South -draw 'text 10,10 Bottom' \
        -gravity West -draw 'text 10,10 Left' \
        -gravity East -draw 'text 10,10 Right' \
        -gravity Center -draw "text 0,0 '$orientation: ${description[$orientation]}'" \
        -gravity Center -draw "text 0,$font_size '$storage'" \
        "$img_annotated"

    log "2. Inverse rotate the image: $inverse_imagemagick: $img_annotated -> $img_transformed"
    magick "$img_annotated" -orient "$inverse_imagemagick" -auto-orient "$img_transformed"

    log "3. Inverse rotate regions in metadata: $inverse_exiftool: $img_transformed -> $img_regions_transformed"
    rm -f "$img_regions_transformed" || true
    exiftool -config $exiftool_rotate_regions_config "-RegionInfo<$inverse_exiftool" "$img_transformed" -o "$img_regions_transformed"

    log "4. Set target orientation in metadata: $orientation: $img_regions_transformed -> $img"
    rm -f "$img" || true
    exiftool "$img_regions_transformed" -n -Orientation="$orientation" -o "$img"

    # sidecar
    if [ "$storage" != "$STOR_EMBEDDED" ]; then 
        log "5. Create sidecar for: $img -> $sidecar"
        rm -f "$sidecar" || true
        exiftool -tagsFromFile "$img" -Orientation -RegionInfo -@ "$exiftool_exif2xmp_args" "$sidecar"

        if [ "$storage" = "$STOR_SIDECAR" ]; then 
            log "6. Metadata storage: $storage. Remove metadata (Orientation, RegionInfo) from the image: $img"
            exiftool -overwrite_original -Orientation= -RegionInfo= "$img"
        fi
    fi

    # print resulting metadata
    log "Final image metadata (Orientation, RegionInfo) from: $img"
    exiftool -struct -j -Orientation -RegionInfo "$img"

    if [ "$storage" != "$STOR_EMBEDDED" ]; then 
        log "Final sidecar metadata (Orientation, RegionInfo) from: $sidecar"
        exiftool -struct -j -Orientation -RegionInfo "$sidecar"
    fi
}

#
# main
#

mkdir -p "$output_dir" "$tmp_dir"

for input_file in "$input_dir"/* ; do
    generate_all_orientations "$input_file" "$STOR_EMBEDDED"
    generate_all_orientations "$input_file" "$STOR_EMBEDDED_SIDECAR"
    generate_all_orientations "$input_file" "$STOR_SIDECAR"
done
