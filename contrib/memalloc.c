#include <stdlib.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

#include <unistd.h>

#define ALPHABET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
#define MB_MAX 37
#define MULTIPLIER 25
#define MALLOC_MB (MULTIPLIER * 1024 * 1024)
#define MALLOC_DELAY 1 /* in seconds */

int main(int argc, char** argv)
  {
    int mb;
    int multiplier = 25;
    char* buffer[MB_MAX] = { NULL };

    for (mb = 0; mb < MB_MAX && (buffer[mb] = malloc (MALLOC_MB)) != NULL; ++mb)
      {
        memset (buffer[mb], ALPHABET[mb % strlen(ALPHABET)], MALLOC_MB);
        printf ("Allocated %d MB\n", MULTIPLIER * (mb + 1));
        sleep (MALLOC_DELAY);
      }

    for (mb = 0; mb < MB_MAX; ++mb)
      {
        if (buffer[mb][0] != ALPHABET[mb % strlen(ALPHABET)])
          {
            printf ("buffer[%d][0] != %c\n", mb, ALPHABET[mb % strlen(ALPHABET)]);
          }
        free (buffer[mb]);
        printf ("Freed %d MB\n", MULTIPLIER * (mb + 1));
        sleep (MALLOC_DELAY);
      }

    return 0;
  }
