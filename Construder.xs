#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <math.h>

#include "vectorlib.c"
#include "world.c"
#include "world_drawing.c"
#include "render.c"
#include "volume_draw.c"


unsigned int ctr_cone_sphere_intersect (double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_x, double sphere_y, double sphere_z, double sphere_rad)
{
  vec3_init(cam,    cam_x, cam_y, cam_z);
  vec3_init(cam_v,  cam_v_x, cam_v_y, cam_v_z);
  vec3_init(sphere, sphere_x, sphere_y, sphere_z);
  vec3_clone(u,  cam);
  vec3_clone(uv, cam_v);
  vec3_clone(d,  sphere);

  vec3_s_mul (uv, sphere_rad / sinl (cam_fov));
  vec3_sub (u, uv);
  vec3_sub (d, u);

  double l = vec3_len (d);

  if (vec3_dot (cam_v, d) >= l * cosl (cam_fov))
    {
       vec3_assign (d, sphere);
       vec3_sub (d, cam);
       l = vec3_len (d);

       if (-vec3_dot (cam_v, d) >= l * sinl (cam_fov))
         return (l <= sphere_rad);
       else
         return 1;
    }
  else
    return 0;
}

MODULE = Games::Construder PACKAGE = Games::Construder::Math PREFIX = ctr_

unsigned int ctr_cone_sphere_intersect (double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_x, double sphere_y, double sphere_z, double sphere_rad);

AV *
ctr_point_aabb_distance (double pt_x, double pt_y, double pt_z, double box_min_x, double box_min_y, double box_min_z, double box_max_x, double box_max_y, double box_max_z)
  CODE:
    vec3_init (pt,   pt_x, pt_y, pt_z);
    vec3_init (bmin, box_min_x, box_min_y, box_min_z);
    vec3_init (bmax, box_max_x, box_max_y, box_max_z);
    unsigned int i;

    double out[3];
    for (i = 0; i < 3; i++)
      {
        out[i] = pt[i];

        if (bmin[i] > bmax[i])
          {
            double swp = bmin[i];
            bmin[i] = bmax[i];
            bmax[i] = swp;
          }

        if (out[i] < bmin[i])
          out[i] = bmin[i];
        if (out[i] > bmax[i])
          out[i] = bmax[i];
      }

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    for (i = 0; i < 3; i++)
      av_push (RETVAL, newSVnv (out[i]));

  OUTPUT:
    RETVAL



AV *
ctr_calc_visible_chunks_at_in_cone (double pt_x, double pt_y, double pt_z, double rad, double cam_x, double cam_y, double cam_z, double cam_v_x, double cam_v_y, double cam_v_z, double cam_fov, double sphere_rad)
  CODE:
    int r = rad;

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    vec3_init (pt, pt_x, pt_y, pt_z);
    vec3_s_div (pt, CHUNK_SIZE);
    vec3_floor (pt);

    int x, y, z;
    for (x = -r; x <= r; x++)
      for (y = -r; y <= r; y++)
        for (z = -r; z <= r; z++)
          {
            vec3_init (chnk,  x, y, z);
            vec3_add (chnk, pt);
            vec3_clone (chnk_p, chnk);

            vec3_sub (chnk, pt);
            if (vec3_len (chnk) < rad)
              {
                vec3_clone (sphere_pos, chnk_p);
                vec3_s_mul (sphere_pos, CHUNK_SIZE);
                sphere_pos[0] += CHUNK_SIZE / 2;
                sphere_pos[1] += CHUNK_SIZE / 2;
                sphere_pos[2] += CHUNK_SIZE / 2;

                if (ctr_cone_sphere_intersect (
                      cam_x, cam_y, cam_z, cam_v_x, cam_v_y, cam_v_z,
                      cam_fov, sphere_pos[0], sphere_pos[1], sphere_pos[2],
                      sphere_rad))
                  {
                    int i;
                    for (i = 0; i < 3; i++)
                      av_push (RETVAL, newSVnv (chnk_p[i]));
                  }
              }
          }

  OUTPUT:
    RETVAL

AV *
ctr_calc_visible_chunks_at (double pt_x, double pt_y, double pt_z, double rad)
  CODE:
    int r = rad;

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    vec3_init (pt, pt_x, pt_y, pt_z);
    vec3_s_div (pt, CHUNK_SIZE);
    vec3_floor (pt);

    int x, y, z;
    for (x = -r; x <= r; x++)
      for (y = -r; y <= r; y++)
        for (z = -r; z <= r; z++)
          {
            vec3_init (chnk,  x, y, z);
            vec3_add (chnk, pt);
            vec3_clone (chnk_p, chnk);
            vec3_sub (chnk, pt);
            if (vec3_len (chnk) < rad)
              {
                int i;
                for (i = 0; i < 3; i++)
                  av_push (RETVAL, newSVnv (chnk_p[i]));
              }
          }

  OUTPUT:
    RETVAL

MODULE = Games::Construder PACKAGE = Games::Construder::Renderer PREFIX = ctr_render_

void *ctr_render_new_geom ();

void ctr_render_clear_geom (void *c);

void ctr_render_draw_geom (void *c);

void ctr_render_free_geom (void *c);

void ctr_render_chunk (int x, int y, int z, void *geom)
  CODE:
    ctr_render_clear_geom (geom);
    ctr_render_chunk (x, y, z, geom);

void
ctr_render_model (unsigned int type, double light, unsigned int xo, unsigned int yo, unsigned int zo, void *geom)
  CODE:
     ctr_render_clear_geom (geom);
     ctr_render_model (type, light, xo, yo, zo, geom);

void ctr_render_init ();

MODULE = Games::Construder PACKAGE = Games::Construder::World PREFIX = ctr_world_

void ctr_world_init (SV *change_cb)
  CODE:
     ctr_world_init ();
     SvREFCNT_inc (change_cb);
     WORLD.chunk_change_cb = change_cb;

SV *
ctr_world_get_chunk_data (int x, int y, int z)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 0);
    if (!chnk)
      {
        XSRETURN_UNDEF;
      }

    int len = CHUNK_ALEN * 4;
    unsigned char *data = malloc (sizeof (unsigned char) * len);
    ctr_world_get_chunk_data (chnk, data);

    RETVAL = newSVpv (data, len);
  OUTPUT:
    RETVAL


void ctr_world_set_chunk_data (int x, int y, int z, unsigned char *data, unsigned int len)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 1);
    assert (chnk);
    ctr_world_set_chunk_from_data (chnk, data, len);
    int lenc = (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE) * 4;
    if (lenc != len)
      {
        printf ("CHUNK DATA LEN DOES NOT FIT! %d vs %d\n", len, lenc);
        exit (1);
      }

    ctr_world_chunk_calc_visibility (chnk);

    ctr_world_emit_chunk_change (x, y, z);

    //d// ctr_world_dump ();

    /*
    unsigned char *datac = malloc (sizeof (unsigned char) * lenc);
    ctr_world_get_chunk_data (chnk, datac);
    int i;
    for (i = 0; i < lenc; i++)
      {
        if (data[i] != datac[i])
          {
            printf ("BUG! AT %d %x %d\n", i, data[i], datac[i]);
            exit (1);
          }
      }
    */

int ctr_world_is_solid_at (double x, double y, double z)
  CODE:
    RETVAL = 0;

    ctr_chunk *chnk = ctr_world_chunk_at (x, y, z, 0);
    if (chnk)
      {
        ctr_cell *c = ctr_chunk_cell_at_abs (chnk, x, y, z);
        ctr_obj_attr *attr = ctr_world_get_attr (c->type);
        RETVAL = attr ? attr->blocking : 0;
      }
  OUTPUT:
    RETVAL

void ctr_world_set_object_type (unsigned int type, unsigned int transparent, unsigned int blocking, double uv0, double uv1, double uv2, double uv3);

void ctr_world_set_object_model (unsigned int type, unsigned int dim, AV *blocks);

AV *
ctr_world_at (double x, double y, double z)
  CODE:
    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    ctr_chunk *chnk = ctr_world_chunk_at (x, y, z, 0);
    if (chnk)
      {
        ctr_cell *c = ctr_chunk_cell_at_abs (chnk, x, y, z);
        av_push (RETVAL, newSViv (c->type));
        av_push (RETVAL, newSViv (c->light));
        av_push (RETVAL, newSViv (c->meta));
        av_push (RETVAL, newSViv (c->add));
        av_push (RETVAL, newSViv (c->visible));
      }

  OUTPUT:
    RETVAL

AV *
ctr_world_chunk_visible_faces (int x, int y, int z)
  CODE:
    ctr_chunk *chnk = ctr_world_chunk (x, y, z, 0);

    RETVAL = newAV ();
    sv_2mortal ((SV *)RETVAL);

    for (z = 0; z < CHUNK_SIZE; z++)
      for (y = 0; y < CHUNK_SIZE; y++)
        for (x = 0; x < CHUNK_SIZE; x++)
          {
            if (chnk->cells[REL_POS2OFFS(x, y, z)].visible)
              {
                av_push (RETVAL, newSViv (chnk->cells[REL_POS2OFFS(x, y, z)].type));
                av_push (RETVAL, newSVnv (x));
                av_push (RETVAL, newSVnv (y));
                av_push (RETVAL, newSVnv (z));
              }
          }

  OUTPUT:
    RETVAL

void
ctr_world_test_binsearch ()
  CODE:
    ctr_axis_array arr;
    arr.alloc = 0;

    printf ("TESTING...\n");
    ctr_axis_array_insert_at (&arr, 0,  10, (void *) 10);
    ctr_axis_array_insert_at (&arr, 1, 100, (void *) 100);
    ctr_axis_array_insert_at (&arr, 2, 320, (void *) 320);
    ctr_axis_array_insert_at (&arr, 1,  11, (void *) 11);
    ctr_axis_array_insert_at (&arr, 0,  9, (void *) 9);
    ctr_axis_array_insert_at (&arr, 5,  900, (void *) 900);
    ctr_axis_array_dump (&arr);

    printf ("SERACHING...\n");
    ctr_axis_node *an = 0;
    int idx = ctr_axis_array_find (&arr, 12, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 13, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 1003, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 11, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 3, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 0, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 320, &an);
    printf ("IDX %d %p\n",idx, an);

    void *ptr = ctr_axis_array_remove_at (&arr, 2);
    printf ("removed %p\n", ptr),
    ctr_axis_array_dump (&arr);
    ptr = ctr_axis_array_remove_at (&arr, 0);
    printf ("removed %p\n", ptr),
    ctr_axis_array_dump (&arr);
    ptr = ctr_axis_array_remove_at (&arr, 3);
    printf ("removed %p\n", ptr),
    ctr_axis_array_dump (&arr);

    ctr_axis_remove (&arr, 100);
    ctr_axis_remove (&arr, 320);
    ctr_axis_remove (&arr, 10);
    ctr_axis_array_dump (&arr);
    ctr_axis_add (&arr, 9, (void *) 9);
    ctr_axis_add (&arr, 320, (void *) 320);
    idx = ctr_axis_array_find (&arr, 11, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 0, &an);
    printf ("IDX %d %p\n",idx, an);
    idx = ctr_axis_array_find (&arr, 400, &an);
    printf ("IDX %d %p\n",idx, an);
    ctr_axis_add (&arr, 11, (void *) 11);
    ctr_axis_add (&arr, 10, (void *) 10);
    ctr_axis_add (&arr, 0, (void *) 0);
    ctr_axis_add (&arr, 50, (void *) 50);
    ctr_axis_array_dump (&arr);
    ctr_axis_remove (&arr, 12);
    ctr_axis_remove (&arr, 50);
    ctr_axis_remove (&arr, 0);
    ctr_axis_remove (&arr, 320);
    ctr_axis_array_dump (&arr);

    ctr_world_init ();
    printf ("WORLD TEST\n\n");

    printf ("*********** ADD 0, 0, 0\n");
    ctr_chunk *chnk = ctr_world_chunk (0, 0, 0, 1);
    assert (chnk);
    ctr_world_dump ();
    printf ("*********** ADD 0, 0, 1\n");
    chnk = ctr_world_chunk (0, 0, 1, 1);
    assert (chnk);
    ctr_world_dump ();
    printf ("*********** ADD 2, 3, 1\n");
    chnk = ctr_world_chunk (2, 3, 1, 1);
    assert (chnk);
    ctr_world_dump ();


void ctr_world_query_load_chunks ();

void ctr_world_query_set_at (unsigned int rel_x, unsigned int rel_y, unsigned int rel_z, AV *cell)
  CODE:
    ctr_world_query_set_at_pl (rel_x, rel_y, rel_z, cell);

void ctr_world_query_unallocated_chunks (AV *chnkposes);

void ctr_world_query_setup (int x, int y, int z, int ex, int ey, int ez);

void ctr_world_query_desetup (int no_update = 0);

void ctr_world_update_light_at (int rx, int ry, int rz, int r)
  CODE:
    vec3_init (pos, rx, ry, rz);
    vec3_s_div (pos, CHUNK_SIZE);
    vec3_floor (pos);
    int chnk_x = pos[0],
        chnk_y = pos[1],
        chnk_z = pos[2];

    //d// printf ("UPDATE LIGHT %d %d %d +- 2 %d\n", chnk_x, chnk_y, chnk_z, r);

    ctr_world_query_setup (
      chnk_x - 1, chnk_y - 1, chnk_z - 1,
      chnk_x + 1, chnk_y + 1, chnk_z + 1
    );

    ctr_world_query_load_chunks ();

    // no concentration: do simple approach here and benchmark!
    // alternative to date is only per-light-radius update once
    // (which might not work properly either)
    int c = (CHUNK_SIZE * 3) / 2;
    int cx = (rx - chnk_x * CHUNK_SIZE) + CHUNK_SIZE;
    int cy = (ry - chnk_y * CHUNK_SIZE) + CHUNK_SIZE;
    int cz = (rz - chnk_z * CHUNK_SIZE) + CHUNK_SIZE;
    int i;
    r -= 1;
    for (i = 0; i <= r; i++)
      {
        int x, y, z;
        for (x = cx - r; x <= cx + r; x++)
          for (y = cy - r; y <= cy + r; y++)
            for (z = cz - r; z <= cz + r; z++)
              {
                ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 1);

                if (i == 0)
                  {
                    if (cur->type == 40) // flood light
                      cur->light = r + 1;
                    else
                      cur->light = 0;
                  }
                else
                  {
                    if (!ctr_world_cell_transparent (cur))
                      continue;

                    ctr_cell *above = ctr_world_query_cell_at (x, y + 1, z, 0);
                    ctr_cell *below = ctr_world_query_cell_at (x, y - 1, z, 0);
                    ctr_cell *left  = ctr_world_query_cell_at (x - 1, y, z, 0);
                    ctr_cell *right = ctr_world_query_cell_at (x + 1, y, z, 0);
                    ctr_cell *front = ctr_world_query_cell_at (x, y, z - 1, 0);
                    ctr_cell *back  = ctr_world_query_cell_at (x, y, z + 1, 0);

                    int ml = above->light;
                    if (below->light > ml)
                      ml = below->light;
                    if (left->light > ml)
                      ml = left->light;
                    if (right->light > ml)
                      ml = right->light;
                    if (front->light > ml)
                      ml = front->light;
                    if (back->light > ml)
                      ml = back->light;

                    if (ml <= 0)
                      continue;

                    if (cur->light < ml)
                      cur->light = ml - 1;
                  }
              }
      }

 //   ctr_world_query_desetup ();

MODULE = Games::Construder PACKAGE = Games::Construder::VolDraw PREFIX = vol_draw_

void vol_draw_init ();

void vol_draw_alloc (unsigned int size);

void vol_draw_set_op (unsigned int op);

void vol_draw_set_dst (unsigned int i);

void vol_draw_set_src (unsigned int i);

void vol_draw_set_dst_range (double a, double b);

void vol_draw_set_src_range (double a, double b);

void vol_draw_set_src_blend (double r);

void vol_draw_val (double val);

void vol_draw_dst_self ();

void vol_draw_sphere_subdiv (float x, float y, float z, float size, int lvl);

void vol_draw_fill_simple_noise_octaves (unsigned int seed, unsigned int octaves, double factor, double persistence);

void vol_draw_menger_sponge_box (float x, float y, float z, float size, int lvl);

void vol_draw_cantor_dust_box (float x, float y, float z, float size, int lvl);

void vol_draw_map_range (float a, float b, float x, float y);

void vol_draw_copy (void *dst_arr);

void vol_draw_dst_to_world (int sector_x, int sector_y, int sector_z)
  CODE:
    int cx = sector_x * CHUNKS_P_SECTOR,
        cy = sector_y * CHUNKS_P_SECTOR,
        cz = sector_z * CHUNKS_P_SECTOR;

    ctr_world_query_setup (
      cx, cy, cz,
      cx + (CHUNKS_P_SECTOR - 1),
      cy + (CHUNKS_P_SECTOR - 1),
      cz + (CHUNKS_P_SECTOR - 1)
    );

    ctr_world_query_load_chunks ();
    int x, y, z;
    for (x = 0; x < DRAW_CTX.size; x++)
      for (y = 0; y < DRAW_CTX.size; y++)
        for (z = 0; z < DRAW_CTX.size; z++)
          {
            ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 1);
            double v = DRAW_DST(x, y, z);
            if (v > 0.5)
              cur->type = 2;
          }

MODULE = Games::Construder PACKAGE = Games::Construder::Region PREFIX = region_

void *region_new_from_vol_draw_dst ()
  CODE:
    double *region =
       malloc ((sizeof (double) * DRAW_CTX.size * DRAW_CTX.size * DRAW_CTX.size) + 1);
    RETVAL = region;

    printf ("REG %p %d\n", region, DRAW_CTX.size);
    region[0] = DRAW_CTX.size;
    region++;
    vol_draw_copy (region);
    printf ("REGVALUES: %f\n", region[0]);
    printf ("REGVALUES: %f\n", region[1]);
    printf ("REGVALUES: %f\n", region[99]);
    printf ("REGVALUES: %f\n", region[99 * 100]);
    printf ("REGVALUES: %f\n", region[100]);

  OUTPUT:
    RETVAL

double region_get_sector_value (void *reg, int x, int y, int z)
  CODE:
    if (!reg)
      XSRETURN_UNDEF;

    double *region = reg;
    int reg_size = region[0];
    region++;
    unsigned xp = x % reg_size;
    if (x < 0) x = -x;
    if (y < 0) y = -y;
    if (z < 0) z = -z;
    x %= reg_size;
    y %= reg_size;
    z %= reg_size;

    double xv = region[x + y * reg_size + z * reg_size * reg_size];
    printf ("REGGET %p %d %d %d %d => %f\n", reg, reg_size, x, y, z, xv);
    RETVAL = xv;

  OUTPUT:
    RETVAL