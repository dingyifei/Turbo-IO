/* Fixed private A/B paths, cap+1 reads and checked durability; no repair read. */
static const char *const tt_paths[]={"/mnt/nand_data/turbo_tiles_v1_0.cfg","/mnt/nand_data/turbo_tiles_v1_1.cfg"};
static int tt_file_read(void *ctx,unsigned bank,uint8_t *p,size_t cap){
 (void)ctx;if(bank>1||cap!=33)return -1;void *f=tap_fs_fopen(tt_paths[bank],"rb");if(!f)return *tap_fs_errno()==2?0:-1;
 size_t used=0;bool ok=true;while(used<cap){size_t n=tap_fs_fread(p+used,1,cap-used,f);if(n>cap-used||tap_fs_ferror(f)){ok=false;break;}used+=n;if(tap_fs_feof(f))break;if(!n){ok=false;break;}}
 if(tap_fs_fclose(f))ok=false;return ok?(int)used:-1;
}
static bool tt_file_write(void *ctx,unsigned bank,const uint8_t *p,size_t n){
 (void)ctx;if(bank>1||n!=32)return false;void *f=tap_fs_fopen(tt_paths[bank],"wb");if(!f)return false;
 size_t used=0;bool ok=true;while(used<n){size_t k=tap_fs_fwrite(p+used,1,n-used,f);if(!k||k>n-used||tap_fs_ferror(f)){ok=false;break;}used+=k;}
 if(ok&&tap_fs_fflush(f))ok=false;if(ok){int fd=tap_fs_fileno(f);if(fd<0||tap_fs_fsync(fd))ok=false;}if(tap_fs_fclose(f))ok=false;return ok;
}
static const TTIO tt_io={NULL,tt_file_read,tt_file_write};
