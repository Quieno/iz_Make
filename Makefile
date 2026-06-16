# =====================
# CONFIG
# =====================

TYPE     = program

PROGRAMS = foo:foo_bin bar:bar_out
BLOCK    = test

OUTDIR   = bin
SRCDIR   = src
INCDIR   = inc
OBJDIR   = obj
3RDDIR   = 3rd

CC       = cc
CFLAGS   = -Wall -Wextra -Werror
CPPFLAGS = -I$(INCDIR)

AR       = ar
ARFLAGS  = rcs

SELF := $(lastword $(MAKEFILE_LIST))

# ==================== SYNC START ====================

#Here Be Dragons#

# ===================== SYNC END =====================

# =====================================================
# Example (minilibx for so_long, exclusive to "client"):
#   THIRD_PARTY = mlx:inc/3rd/client:libmlx_Linux.a
#   mlx = -lXext -lX11 -lm
# =====================================================

THIRD_PARTY =

$(foreach e,$(THIRD_PARTY), \
  $(eval _tp_path := $(word 2,$(subst :, ,$(e)))) \
  $(eval _tp_art  := $(word 3,$(subst :, ,$(e)))) \
  $(eval _tp_id   := $(word 1,$(subst :, ,$(e)))) \
  $(eval _tp_name := $(notdir $(_tp_path))) \
  $(eval _tp_dest := $(if $(filter $(_tp_name):%,$(PROGRAMS)),$(_tp_name),COMMON)) \
  $(eval $(_tp_dest)_TP_ARTIFACTS := $($(_tp_dest)_TP_ARTIFACTS) $(_tp_path)/$(_tp_art)) \
  $(eval $(_tp_dest)_TP_INCLUDES  := $($(_tp_dest)_TP_INCLUDES) -I$(_tp_path)) \
  $(eval $(_tp_dest)_TP_LIBS      := $($(_tp_dest)_TP_LIBS) $($(_tp_id))) \
  $(eval TP_PATHS := $(TP_PATHS) $(_tp_path)) \
)

TP_INCLUDES = $(COMMON_TP_INCLUDES) $(foreach sfx,$(ALL_SUFFIXES),$($(sfx)_TP_INCLUDES))
TP_ARTIFACTS = $(COMMON_TP_ARTIFACTS) $(foreach sfx,$(ALL_SUFFIXES),$($(sfx)_TP_ARTIFACTS))

# =====================
# DERIVED
# =====================

COMMON_OBJS     = $(COMMON_SRCS:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
INCDIRS_FLAGS   = $(addprefix -I,$(INCLUDE_DIRS))
MODULE_CPPFLAGS = $(foreach m,$(MODULE_PATHS),-I$(m)/inc -I$(m))

ALL_SUFFIXES    = $(foreach p,$(PROGRAMS),$(word 1,$(subst :, ,$(p))))
ACTIVE_SUFFIXES = $(foreach p,\
                    $(filter-out $(foreach b,$(BLOCK),$(b):%),$(PROGRAMS)),\
                    $(word 1,$(subst :, ,$(p))))

# =====================
# PHONY
# =====================

.PHONY: all build clean fclean re sync \
        relay-build relay-clean relay-fclean relay-thirdparty \
        relay-thirdparty-clean relay-thirdparty-fclean \
        $(ALL_SUFFIXES)

all: build

build: relay-build $(ACTIVE_SUFFIXES)

# =====================
# RELAY
# =====================

relay-build: relay-thirdparty
	@for d in $(MODULE_PATHS); do \
		$(MAKE) -C "$$d" build; \
	done

relay-thirdparty:
	@for d in $(TP_PATHS); do \
		$(MAKE) -C "$$d"; \
	done

relay-thirdparty-clean:
	@for d in $(TP_PATHS); do \
		$(MAKE) -C "$$d" clean 2>/dev/null || true; \
	done

relay-thirdparty-fclean:
	@for d in $(TP_PATHS); do \
		$(MAKE) -C "$$d" fclean 2>/dev/null || true; \
	done

relay-clean:
	@for d in $(MODULE_PATHS); do \
		$(MAKE) -C "$$d" clean; \
	done

relay-fclean:
	@for d in $(MODULE_PATHS); do \
		$(MAKE) -C "$$d" fclean; \
	done

# =====================
# COMPILATION
# =====================

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(INCDIRS_FLAGS) $(MODULE_CPPFLAGS) $(TP_INCLUDES) $(CFLAGS) -MMD -MP -c $< -o $@


ifeq ($(TYPE),library)
  ifeq ($(OUTDIR),root)
define SUFFIX_RULE
$(1)_OBJS = $$($(1)_SRCS:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
$(1): $$(COMMON_OBJS) $$($(1)_OBJS)
	$(AR) $(ARFLAGS) $$($(1)_NAME).a $$^
endef
  else
define SUFFIX_RULE
$(1)_OBJS = $$($(1)_SRCS:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
$(1): $$(COMMON_OBJS) $$($(1)_OBJS)
	@mkdir -p $(OUTDIR)
	$(AR) $(ARFLAGS) $(OUTDIR)/$$($(1)_NAME).a $$^
endef
  endif
else
  ifeq ($(OUTDIR),root)
define SUFFIX_RULE
$(1)_OBJS = $$($(1)_SRCS:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
$(1): $$(COMMON_OBJS) $$($(1)_OBJS) $$(COMMON_ARTIFACTS) $$($(1)_ARTIFACTS) $$(COMMON_TP_ARTIFACTS) $$($(1)_TP_ARTIFACTS)
	$(CC) $(CPPFLAGS) $(CFLAGS) $$^ $$(COMMON_TP_LIBS) $$($(1)_TP_LIBS) -o $$($(1)_NAME)
endef
  else
define SUFFIX_RULE
$(1)_OBJS = $$($(1)_SRCS:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
$(1): $$(COMMON_OBJS) $$($(1)_OBJS) $$(COMMON_ARTIFACTS) $$($(1)_ARTIFACTS) $$(COMMON_TP_ARTIFACTS) $$($(1)_TP_ARTIFACTS)
	@mkdir -p $(OUTDIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $$^ $$(COMMON_TP_LIBS) $$($(1)_TP_LIBS) -o $(OUTDIR)/$$($(1)_NAME)
endef
  endif
endif

$(foreach p,$(PROGRAMS),\
  $(eval $(call SUFFIX_RULE,$(word 1,$(subst :, ,$(p))))))


DEPS = $(COMMON_OBJS:.o=.d) \
       $(foreach sfx,$(ALL_SUFFIXES),$($(sfx)_OBJS:.o=.d))

-include $(DEPS)

# =====================
# CLEAN
# =====================

clean:
	@$(MAKE) relay-clean
	@$(MAKE) relay-thirdparty-clean
	@rm -rf $(OBJDIR)

ifeq ($(OUTDIR),root)
  ifeq ($(TYPE),library)
  fclean:
	@$(MAKE) relay-fclean
	@$(MAKE) relay-thirdparty-fclean
	@rm -rf $(OBJDIR)
	@rm -f $(TP_ARTIFACTS)
	@$(if $(ALL_SUFFIXES),rm -f $(foreach sfx,$(ALL_SUFFIXES),$($(sfx)_NAME).a))
  else
  fclean:
	@$(MAKE) relay-fclean
	@$(MAKE) relay-thirdparty-fclean
	@rm -rf $(OBJDIR)
	@rm -f $(TP_ARTIFACTS)
	@$(if $(ALL_SUFFIXES),rm -f $(foreach sfx,$(ALL_SUFFIXES),$($(sfx)_NAME)))
  endif
else
fclean:
	@$(MAKE) relay-fclean
	@$(MAKE) relay-thirdparty-fclean
	@rm -rf $(OBJDIR) $(OUTDIR)
	@rm -f $(TP_ARTIFACTS)
endif

re: fclean build

# =====================
# SYNC ENGINE
# =====================

sync:
	@set -e; \
	tmp=$$(mktemp) || exit 1; \
	\
	awk 'BEGIN{p=1} \
	     /^# ==================== SYNC START ====================/ {p=0} \
	     p {print}' "$(SELF)" > $$tmp; \
	printf '# ==================== SYNC START ====================\n' >> $$tmp; \
	\
	MODULE_PATHS=""; \
	\
	ALL_MOD_DIRS=`find $(INCDIR) -type f -name Makefile -not -path "*/$(3RDDIR)/*" 2>/dev/null -exec dirname {} \; | sort -u`; \
	\
	for d in $$ALL_MOD_DIRS; do \
		nested=0; \
		for o in $$ALL_MOD_DIRS; do \
			[ "$$o" = "$$d" ] && continue; \
			case "$$d" in \
				"$$o"/*) nested=1 ;; \
			esac; \
		done; \
		[ $$nested -eq 1 ] && continue; \
		\
		rel="$${d#$(INCDIR)/}"; \
		[ "$$rel" = "$$d" ] && continue; \
		topdir="$${rel%%/*}"; \
		\
		is_sfx=0; \
		for p in $(PROGRAMS); do [ "$${p%%:*}" = "$$topdir" ] && is_sfx=1; done; \
		is_blk=0; \
		for b in $(BLOCK); do [ "$$b" = "$$topdir" ] && is_blk=1; done; \
		[ $$is_blk -eq 1 ] && [ $$is_sfx -eq 0 ] && continue; \
		\
		MODULE_PATHS="$$MODULE_PATHS $$d"; \
		modtype=`awk '/^TYPE[[:space:]]*=/{print $$3; exit}' "$$d/Makefile"`; \
		[ "$$modtype" = "library" ] || continue; \
		modoutdir=`awk '/^OUTDIR[[:space:]]*=/{print $$3; exit}' "$$d/Makefile"`; \
		modblock=`awk '/^BLOCK[[:space:]]*=/ \
		               {sub(/^BLOCK[[:space:]]*=[[:space:]]*/,""); print; exit}' \
		               "$$d/Makefile"`; \
		awk '/^PROGRAMS[[:space:]]*=/ { \
		         in_p=1; \
		         sub(/^PROGRAMS[[:space:]]*=[[:space:]]*/,""); \
		         gsub(/[\\]/,""); gsub(/[[:space:]]/,""); \
		         if ($$0 != "") print; next \
		     } \
		     in_p && /^[[:space:]]/ { \
		         gsub(/[\\[:space:]]/,""); \
		         if ($$0 != "") print; next \
		     } \
		     in_p { in_p=0 }' "$$d/Makefile" | while IFS= read -r o; do \
			[ -z "$$o" ] && continue; \
			msfx=$${o%%:*}; \
			mname=$${o#*:}; \
			mblocked=0; \
			for b in $$modblock; do [ "$$b" = "$$msfx" ] && mblocked=1; done; \
			[ $$mblocked -eq 1 ] && continue; \
			if [ -z "$$modoutdir" ] || [ "$$modoutdir" = "root" ]; then \
				artpath="$$d/$$mname.a"; \
			else \
				artpath="$$d/$$modoutdir/$$mname.a"; \
			fi; \
			if [ $$is_sfx -eq 1 ]; then \
				printf '%s\n' "$$artpath" >> "$$tmp.art.$$topdir"; \
			else \
				printf '%s\n' "$$artpath" >> "$$tmp.art.common"; \
			fi; \
		done; \
	done; \
	\
	printf '%s\n' $$MODULE_PATHS | \
		awk 'NF{l[++n]=$$0} END{r="MODULE_PATHS :="; \
		     for(i=1;i<=n;i++) r=r" \\\n\t"l[i]; print r}' >> $$tmp; \
	printf '\n' >> $$tmp; \
	\
	COMMON=""; \
	for f in `find $(SRCDIR) -type f -name "*.c" -not -path "*/$(3RDDIR)/*" 2>/dev/null | sort`; do \
		rel="$${f#$(SRCDIR)/}"; \
		topdir="$${rel%%/*}"; \
		if [ "$$topdir" = "$$rel" ]; then \
			COMMON="$$COMMON $$f"; \
			continue; \
		fi; \
		is_sfx=0; is_blk=0; \
		for p in $(PROGRAMS); do [ "$${p%%:*}" = "$$topdir" ] && is_sfx=1; done; \
		for b in $(BLOCK);    do [ "$$b"        = "$$topdir" ] && is_blk=1; done; \
		[ $$is_sfx -eq 0 ] && [ $$is_blk -eq 0 ] && COMMON="$$COMMON $$f"; \
	done; \
	printf '%s\n' $$COMMON | \
		awk 'NF{l[++n]=$$0} END{r="COMMON_SRCS :="; \
		     for(i=1;i<=n;i++) r=r" \\\n\t"l[i]; print r}' >> $$tmp; \
	printf '\n' >> $$tmp; \
	\
	cat "$$tmp.art.common" 2>/dev/null | sort -u | \
		awk 'NF{l[++n]=$$0} END{r="COMMON_ARTIFACTS :="; \
		     for(i=1;i<=n;i++) r=r" \\\n\t"l[i]; print r}' >> $$tmp; \
	printf '\n' >> $$tmp; \
	\
	INCDIRS=""; \
	for d in `find $(INCDIR) -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort`; do \
		[ -f "$$d/Makefile" ] && continue; \
		dirn=`basename "$$d"`; \
		[ "$$dirn" = "$(3RDDIR)" ] && continue; \
		is_blk=0; \
		for b in $(BLOCK); do [ "$$b" = "$$dirn" ] && is_blk=1; done; \
		[ $$is_blk -eq 1 ] && continue; \
		INCDIRS="$$INCDIRS $$d"; \
	done; \
	printf '%s\n' $$INCDIRS | \
		awk 'NF{l[++n]=$$0} END{r="INCLUDE_DIRS :="; \
		     for(i=1;i<=n;i++) r=r" \\\n\t"l[i]; print r}' >> $$tmp; \
	printf '\n' >> $$tmp; \
	\
	for p in $(PROGRAMS); do \
		sfx=$${p%%:*}; \
		name=$${p#*:}; \
		printf "$${sfx}_NAME := $${name}\n" >> $$tmp; \
		find "$(SRCDIR)/$$sfx" -type f -name "*.c" -not -path "*/$(3RDDIR)/*" 2>/dev/null | sort | \
			awk -v v="$${sfx}_SRCS" \
			    'NF{l[++n]=$$0} END{r=v" :="; \
			     for(i=1;i<=n;i++) r=r" \\\n\t"l[i]; print r}' >> $$tmp; \
		printf '\n' >> $$tmp; \
		cat "$$tmp.art.$$sfx" 2>/dev/null | sort -u | \
			awk -v v="$${sfx}_ARTIFACTS" \
			    'NF{l[++n]=$$0} END{r=v" :="; \
			     for(i=1;i<=n;i++) r=r" \\\n\t"l[i]; print r}' >> $$tmp; \
		printf '\n' >> $$tmp; \
	done; \
	\
	rm -f "$$tmp.art."*; \
	\
	printf '# ===================== SYNC END =====================\n' >> $$tmp; \
	\
	awk 'found {print} \
	     /^# ===================== SYNC END =====================/ {found=1}' \
	     "$(SELF)" >> $$tmp; \
	\
	mv $$tmp "$(SELF)"; \
	\
	for d in $$MODULE_PATHS; do \
		$(MAKE) -C "$$d" sync; \
	done
