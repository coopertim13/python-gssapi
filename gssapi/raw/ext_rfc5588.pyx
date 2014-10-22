from gssapi.raw.cython_types cimport *
from gssapi.raw.names cimport Name
from gssapi.raw.creds cimport Creds
from gssapi.raw.oids cimport OID
from gssapi.raw.cython_converters cimport c_create_mech_list
GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from gssapi.raw.cython_converters cimport c_get_mech_oid_set
from gssapi.raw.cython_converters cimport c_c_ttl_to_py, c_py_ttl_to_c

from gssapi.raw.named_tuples import StoreCredResult
from gssapi.raw.misc import GSSError

cdef extern from "gssapi.h":
    OM_uint32 gss_store_cred(OM_uint32 *min_stat,
                             gss_cred_id_t input_creds,
                             gss_cred_usage_t cred_usage,
                             gss_OID desired_mech,
                             OM_uint32 overwrite_cred,
                             OM_uint32 default_cred,
                             gss_OID_set *elements_stored,
                             gss_cred_usage_t *actual_usage) nogil


def store_cred(Creds creds not None, cred_usage='both', OID mech=None,
               bint overwrite=False, bint set_default=False):
    cdef gss_OID desired_mech
    if mech is not None:
        desired_mech = &mech.raw_oid
    else:
        desired_mech = GSS_C_NO_OID

    cdef gss_cred_usage_t usage
    if cred_usage == 'initiate':
        usage = GSS_C_INITIATE
    elif cred_usage == 'accept':
        usage = GSS_C_ACCEPT
    else:
        usage = GSS_C_BOTH

    cdef gss_cred_id_t c_creds = creds.raw_creds

    cdef gss_OID_set actual_mech_types
    cdef gss_cred_usage_t actual_usage

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_store_cred(&min_stat, c_creds, usage,
                                  desired_mech, overwrite,
                                  set_default, &actual_mech_types,
                                  &actual_usage)

    if maj_stat == GSS_S_COMPLETE:
        if actual_usage == GSS_C_INITIATE:
            py_actual_usage = 'initiate'
        elif actual_usage == GSS_C_ACCEPT:
            py_actual_usage = 'accept'
        else:
            py_actual_usage = 'both'

        return StoreCredResult(c_create_mech_list(actual_mech_types),
                               py_actual_usage)
    else:
        raise GSSError(maj_stat, min_stat)
